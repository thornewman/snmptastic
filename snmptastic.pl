#!/usr/bin/perl
#
# snmptastic.pl
#
# SNMP & SCP Based Network Monitor Tool
# Originally written in September, 2006 by Thor Newman
#
# VERSION 1.9
#
##################################################################################

$| = 1;

$SIG{'TERM'} = \&catch_term;

use POSIX qw(setsid);
use strict;

use File::Copy;
use Net::SNMP;
use Net::TFTP;
use Net::SMTP;
use Cisco::CopyConfig;
use XML::Simple;
use Data::Dumper;


##################################################################################
## GLOBALS
##################################################################################

my $configFile = shift or die "Specify a valid XML Configuration file!\n";
my $logFile;
my $diffLog;
my $tracking;
my $VERBOSE;
my $LOGGING;
my $LOG_DIFFERENTIAL;
my $numDevices;
my $tftp;
my $iteration	= 1;
my $RUNNING	= 0;
my @deviceNames;
my @deviceCommunity;
my @deviceDestinations;
## XML Configuration File Hash
my $config;


##################################################################################
## MAIN BODY
##################################################################################

## Load Configuration
loadXMLConfig();

## Set global variables
setGlobals();

## Sanity Check Configuration
verifyConfiguration();

## Log startup information
logEvent("*** Started $0");
print Dumper($config) if $VERBOSE;
logEvent("Tracking Directory set to $tracking");
logEvent("Differential Command set to $config->{'diff_command'}");
logEvent("Configuration changes will be sent to $config->{'notification'}->{'notify-configuration-changes'}") if  $config->{'notification'}->{'notify-configuration-changes'};
logEvent("Using Mail Template $config->{'notification'}->{'mail-template'}") if ( -e  $config->{'notification'}->{'mail-template'} );
logEvent("Configuration changes will be logged to $diffLog") if ($config->{'log_differential'} and $diffLog);
logEvent("Polling Frequency set to $config->{'iteration_frequency'} seconds");
createDummyDevices() if $numDevices < 1;
logEvent("There are no Devices defined to monitor") if $numDevices < 1;
logEvent("Insufficient Devices Present -- Minimum of 2 Devices Required -- Halting Execution") if $numDevices < 1;
exit 1 if $numDevices < 1;

## Log all monitored devices
logDevices();


##
## Main Loop
##

daemonize();
logEvent("Entering Main Loop");
while ( $RUNNING ) {
    logEvent("*** $0 Starting Iteration $iteration") if $VERBOSE;
    iterateDevices();
    cleanTrackingDirectory();
    logEvent("*** $0 Iteration $iteration Complete") if $VERBOSE;
    logEvent("Sleeping for $config->{'iteration_frequency'} seconds") if $VERBOSE;
    sleep ( $config->{'iteration_frequency'} );
    $iteration++;
}
logEvent("Exited Main Loop");
logEvent("*** $0 Daemon Halted");

##################################################################################
## END OF MAIN BODY
##################################################################################



##################################################################################
## FUNCTIONS
##################################################################################


##
## Catches TERM signal to terminate the daemon
##
sub catch_term() {
    logEvent("Caught TERM Signal");
    $RUNNING = 0;
}


##
## Parses State Files
## and removes stale files from tracking directory
##
sub cleanTrackingDirectory() {
    
    my $tracking = $config->{'tracking'};
    my @stateFiles = <$tracking/*-state-file>;
    my @trackingContents = <$tracking/*>;
    my @stateData;
    my $Statecount;
    
    logEvent("Entered cleanTrackingDirectory()") if $VERBOSE;
    
    ##
    ## Load all State files entries into an array
    ##
    
    foreach my $file ( @stateFiles ) {
        
        chomp $file;
        
        #logEvent("Checking State File $file") if $VERBOSE;
        
        open IN,"<$file" or return 0;
        while (<IN>) {
            chomp;
            push @stateData, $_;
            $Statecount++;
        }
        close IN;
    }
    
    logEvent("Parsed $Statecount State Files") if $VERBOSE;
    
    my $stateData = join " ",@stateData;
    ##
    ## Iterate @stateData array and unlink any non-state files
    ##
    foreach my $file ( @trackingContents ) {
        
        next if $file =~ /.*-state-file/g;
        $file =~ s/$tracking\///g;
        
        if ($stateData =~ m/$file/ ) {
            
            # logEvent("File $file is in state table") if $VERBOSE;
            
        } else {
            
            logEvent("Deleting $tracking/$file") if $VERBOSE;
            unlink "$tracking/$file" or logEvent("$!");
            
        }
    }
    logEvent("Exiting cleanTrackingDirectory()") if $VERBOSE;
}


##
## Outputs a list of monitored devices at the beginning 
## of execution to the logging file
##
sub logDevices() {
    logEvent("The following devices will be monitored");
    
    foreach my $key ( sort keys %{$config->{'device'}} ) {
        logEvent("Monitoring $config->{'device'}->{$key}->{'type'} device named $key at $config->{'device'}->{$key}->{'address'}");
    }
    
}


##
## Iterates through all devices in the $config hashtable
##
sub iterateDevices() {
    
    foreach my $key ( keys %{$config->{'device'}} ) {
        
        
        #logEvent("Processing Device $key") if $config->{'logging_verbose'};
        my $timestamp = time();
        my $name = $key;
        my $target = $config->{'device'}->{$key}->{'address'};
        my $community = $config->{'device'}->{$key}->{'community'};
        my $fname = $key;
        $fname .= "." . $timestamp;
        
        if ( $config->{'device'}->{$key}->{'type'} =~ /cisco/i ) {
            logEvent("Calling getCiscoConfiguration() with parameters: $target $community $tftp $fname")  if $VERBOSE;
            unless ( getCiscoConfiguration($target, $community, $tftp, $fname) ) {
                logEvent("Device $name($target) Configuration Retrieval Failed");
                next;
            }
            
            ##
            ## Transfer the new configuration to the tracking directory
            ##
            my $src = $config->{'tftp'}->{'directory'} . "/" . "$fname";
            chmod 0600,$src;
            move( $src, $tracking );
            
            ##
            ## Check the state file
            ##
            unless ( -e "$tracking/$name-state-file" ) {
                logEvent("No state file found for $name");
                unless ( createStateFile($name,$fname)) {
                    logEvent("Unable To Create State File: $tracking$fname");
                }
            }
            
            ##
            ## Perform a diff, and update the state file
            ##
            if (my $lastFile = readStateFile($name)) {
                unless ( $lastFile eq $fname ) {
                    my $diff_command;
                    
                    if ( $config->{'device'}->{$key}->{'diff_command'} ) {
                        $diff_command = "$config->{'device'}->{$key}->{'diff_command'}";
                    } else {
                        $diff_command = "$config->{'diff_command'}";
                    }
                    
                    logEvent("Executing Differential Command: $diff_command $tracking/$lastFile $tracking/$fname") if $VERBOSE;
                    my $diff = `$diff_command $tracking/$lastFile $tracking/$fname`;
                    
                    if ( $diff ) {
                        sendDiffNotification($name,$target,$diff);
                        #sendDiffbySMTPClient($name,$target,$diff);
                        
                        
                        unless ( updateStateFile($name,$fname) ){
                            logEvent("WARNING Error Updating State File $tracking/$name-state-file");
                            logEvent("WARNING State tracking of device $name cannot be performed.");
                        }
                    } else {
                        logEvent("No Configuration changes found for $name -- erasing file $tracking/$fname") if $VERBOSE;
                        unlink "$tracking/$fname";
                    }
                    
                }
            } else {
                logEvent("Error Reading State File for $name");
            }
            
        } elsif ( $config->{'device'}->{$key}->{'type'} =~ /scp/i ) {
            my $name = $key;
            my $type = $config->{'device'}->{$key}->{'type'};
            my $address = $config->{'device'}->{$key}->{'address'};
            my $sshkey = $config->{'device'}->{$key}->{'sshkey'};
            my $fileList = $config->{'device'}->{$key}->{'file'};
            my $sshuser = $config->{'device'}->{$key}->{'sshuser'};
            
            logEvent("Calling getSCPDevice() with parameters: $name $address $sshkey $sshuser $fileList") if $VERBOSE;
            
            getSCPDevice($name,$address,$sshkey,$sshuser,$fileList);
            
            
        } elsif ( $config->{'device'}->{$key}->{'type'} =~ /hp/i ) {
            my $name = $key;
            my $type = $config->{'device'}->{$key}->{'type'};
            my $address = $config->{'device'}->{$key}->{'address'};
            my $community = $config->{'device'}->{$key}->{'community'};
            
            logEvent("Calling getHPDevice() with parameters: $name $address $community") if $VERBOSE;
            getHPDevice($name,$address,$community);
        } elsif ( $config->{'device'}->{$key}->{'type'} =~ /foundry/i ) {
            my $name = $key;
            my $type = $config->{'device'}->{$key}->{'type'};
            my $address = $config->{'device'}->{$key}->{'address'};
            my $community = $config->{'device'}->{$key}->{'community'};
            my $enable = $config->{'device'}->{$key}->{'enable'};
            logEvent("Calling getFoundryDevice() with parameters: $name $address $community $enable") if $VERBOSE;
            getFoundryDevice($name,$address,$community, $enable);
        }
        
    }
    
}


##
## Handles the retreival of Foundy devices
##

sub getFoundryDevice() {
    
    my $name = $_[0];
    my $address = $_[1];
    my $community = $_[2];
    my $enable = $_[3];
    my $destinationDir = $config->{'tracking'};
    my $tftpDir =  $config->{'tftp'}->{'directory'};
    my $time = time();
    my $fname = $name . "." . $time;
    
    
    logEvent("Calling getFoundryConfig() with parameters: $name $community $enable $tftpDir, $fname") if $VERBOSE;
    unless ( getFoundryConfig($address,$community,$enable,$tftpDir,$fname ) == 1 ) {
        logEvent("Error retrieving configuration from $name @ $address");
        return 0;
    }
    
    unless ( -e "$tracking/$name-state-file" ) {
        logEvent("No state file found for $name");
        unless ( createStateFile($name,"$name.$time")) {
            logEvent("Unable To Create State File: $tracking/$name-state-file");
            return 0;
        }
    }
    
    
    if (my $lastFile = readStateFile($name) ) {
        
        unless ( $lastFile eq "$name.$time" ) {
            
            
            my $diff_command;
            
            if ( $config->{'device'}->{$name}->{'diff_command'} ) {
                $diff_command = "$config->{'device'}->{$name}->{'diff_command'}";
            } else {
                $diff_command = "$config->{'diff_command'}";
            }
            
            logEvent("Executing Differential Command: $diff_command $tracking/$lastFile $tracking/$name.$time") if $VERBOSE;
            my $diff = `$diff_command $tracking/$lastFile $tracking/$name.$time`;
            
            
            if ( $diff ) {
                sendDiffNotification($name,$address,$diff);
                unless ( updateStateFile($name,"$name.$time") ){
                    logEvent("WARNING Error Updating State File $tracking/$name-state-file");
                    logEvent("WARNING State tracking of device $name cannot be performed.");
                }
            } else {
                logEvent("No Configuration changes found for $name -- erasing file $tracking/$name.$time") if $VERBOSE;
                unlink "$tracking/$name.$time";
            }
        }
        
    } else {
        logEvent("Error Reading State File for $name");
    }
}



##
## SNMP process to retrieve Foundry Configuration
##

sub getFoundryConfig() {
    
    my $address = $_[0];
    my $community = $_[1];
    my $enable = $_[2];
    my $directory = $_[3];
    my $name = $_[4];
    my $tftpDest = $directory . "/" . $name;
    
    
    my $ENABLE_OID = '.1.3.6.1.4.1.1991.1.1.2.1.15.0';
    my $TFTPSERVER_OID = '.1.3.6.1.4.1.1991.1.1.2.1.5.0';
    my $TFTPFILENAME_OID = '.1.3.6.1.4.1.1991.1.1.2.1.8.0';
    my $ACTION_OID = '.1.3.6.1.4.1.1991.1.1.2.1.9.0';
    
    my ($session, $error) = Net::SNMP->session(
    -hostname       => $address,
    -version        => 'snmpv2c',
    -community      => $community,
    -port           => 161
    );
    
    
    if ( !defined($session) ) {
        logEvent("Error Creating SNMP Session: $error");
        return 0;
    }
    
    logEvent("Sending SNMP packet to $address: $enable $tftp $name 22") if $VERBOSE;
    
    
    my $result = $session->set_request(
    -varbindlist => [
    ($ENABLE_OID, OCTET_STRING, $enable),
    ($TFTPSERVER_OID,IPADDRESS, $tftp),
    ($TFTPFILENAME_OID,OCTET_STRING, $name ),
    ($ACTION_OID, INTEGER, 22)
    ]
    );
    
    if ( !defined($result) ) {
        my $err = $session->error;
        logEvent("Device $address returned an SNMP error: $err");
        $session->close;
        return 0;
    }
    
    my $count = 0;
    my $check;
    
    
    ##
    ## Retrieves configuration file by SNMP
    ##
    while ( $check->{$ACTION_OID} != 1 ) {
        ##
        ## Verify the Packet
        ##
        $check = $session->get_request( $ACTION_OID );
        $count++;
        logEvent("Check $count returned code of $check->{$ACTION_OID}") if $VERBOSE;
        
        if ( $count >= 5 ) {
            logEvent("Configuration Retrieval of device $name @ $address unsuccessful");
            return 0;
        }
        
        sleep 1 unless ( $check->{$ACTION_OID} == 1 );
        
    }
    
    ##
    ## Verify the file exists
    ##
    unless ( -e $tftpDest ) {
        logEvent("Configuration file $name not successfully retrieved from device $name @ $address");
        return 0;
    }
    
    
    ##
    ## Transfer the new configuration to the tracking directory
    ##
    
    chmod 0600,$tftpDest;
    logEvent("Moving: $tftpDest to $tracking") if $VERBOSE;
    move( $tftpDest, $tracking );
    
    
    return 1;
    
    
}



##
## Handles retrieval of HP devices
##
sub getHPDevice() {
    my $name = $_[0];
    my $address = $_[1];
    my $community = $_[2];
    
    my $destinationDir = $config->{'tracking'};
    enableHpTFTPServer($address,$community);
    
    my $time = time();
    my $TFTP = Net::TFTP->new( $address, BlockSize => 1024 );
    $TFTP->ascii;
    $TFTP->get("running-config","$destinationDir/$name.$time");
    
    chmod 0600,$destinationDir/$name.$time;
    
    if ( $TFTP->error ) {
        my $err = $TFTP->error;
        logEvent("Device $name returned an error during configuration retrieval: $err");
        disableHpTFTPServer($address,$community);
        return 0;
    }
    
    unless ( -e "$tracking/$name-state-file" ) {
        logEvent("No state file found for $name");
        unless ( createStateFile($name,"$name.$time")) {
            logEvent("Unable To Create State File: $tracking/$name-state-file");
        }
    }
    
    if (my $lastFile = readStateFile($name) ) {
        
        unless ( $lastFile eq "$name.$time" ) {
            
            
            my $diff_command;
            
            if ( $config->{'device'}->{$name}->{'diff_command'} ) {
                $diff_command = "$config->{'device'}->{$name}->{'diff_command'}";
            } else {
                $diff_command = "$config->{'diff_command'}";
            }
            
            logEvent("Executing Differential Command: $diff_command $tracking/$lastFile $tracking/$name.$time") if $VERBOSE;
            my $diff = `$diff_command $tracking/$lastFile $tracking/$name.$time`;
            
            
            if ( $diff ) {
                sendDiffNotification($name,$address,$diff);
                unless ( updateStateFile($name,"$name.$time") ){
                    logEvent("WARNING Error Updating State File $tracking/$name-state-file");
                    logEvent("WARNING State tracking of device $name cannot be performed.");
                }
            } else {
                logEvent("No Configuration changes found for $name -- erasing file $tracking/$name.$time") if $VERBOSE;
                unlink "$tracking/$name.$time";
            }
        }
        
    } else {
        logEvent("Error Reading State File for $name");
    }
    
    
    disableHpTFTPServer($address,$community);
}

##
## Handles retrieval of SCP based devices
##
sub getSCPDevice() {
    my ($name,$address,$sshkey,$sshuser,$fileList) = @_;
    my @fileArray = split ",",$fileList;
    
    
    foreach my $file ( @fileArray ) {
        logEvent("Retrieving file $file from $name @ $address") if $VERBOSE;
        my $time = time();
        my $cleanedFile = $file;
        $cleanedFile =~ s/\//-/g;
        my $scp = "scp -i $sshkey $sshuser\@$address:$file $config->{'tracking'}/$name-$cleanedFile.$time";
        logEvent("Executing Command: $scp") if $VERBOSE;
        my $output = `$scp`;
        chmod 0600,$tracking/$name-$cleanedFile.$time;
        
        logEvent("Error retrieving file $file from $name @ $address") unless ( -e "$tracking/$name-$cleanedFile.$time" );
        
        unless ( -e "$tracking/$name-state-file" ) {
            logEvent("No state file found for $name");
            unless ( createStateFile($name,"$name-$cleanedFile.$time")) {
                logEvent("Unable To Create State File: $tracking/$name-state-file");
            }
        }
        
        ##
        ## Perform a diff, and update the state file
        ##
        
        if (my $lastFile = readStateFile($name) ) {
            
            unless ( "$lastFile" eq "$name-$cleanedFile.$time" ) {
                
                my $diff_command;
                
                if ( $config->{'device'}->{$name}->{'diff_command'} ) {
                    $diff_command = "$config->{'device'}->{$name}->{'diff_command'}";
                } else {
                    $diff_command = "$config->{'diff_command'}";
                }
                
                logEvent("Executing Differential Command: $diff_command $tracking/$lastFile $tracking/$name-$cleanedFile.$time") if $VERBOSE;
                my $diff = `$diff_command $tracking/$lastFile $tracking/$name-$cleanedFile.$time`;
                
                
                
                if ( $diff ) {
                    sendDiffNotification($name,$address,$diff);
                    unless ( updateStateFile($name,"$name-$cleanedFile.$time") ){
                        logEvent("WARNING Error Updating State File $tracking/$name-state-file");
                        logEvent("WARNING State tracking of device $name cannot be performed.");
                    }
                } else {
                    logEvent("No Configuration changes found for $name -- erasing file $tracking/$name-$cleanedFile.$time") if $VERBOSE;
                    unlink "$tracking/$name-$cleanedFile.$time";
                }
            }
            
        } else {
            logEvent("Error Reading State File for $name-$cleanedFile");
        }
        
        
    }
    
    
}

###
### Send Email Old-school way piping through Sendmail
###
sub sendDiffNotification() {
    my $name = $_[0];
    my $target = $_[1];
    my $diff = $_[2];
    
    ## Mail template file
    my $template = $config->{'notification'}->{'mail-template'};
    
    my $recipients = $config->{'notification'}->{'notify-configuration-changes'};
    my $from = $config->{'notification'}->{'notify-from-address'};
    my $mailer = "/usr/sbin/sendmail -t";
    chomp($recipients);
    $recipients =~ s/\n//g;
    
    ##
    ## Hashtable of variable substitions
    ## Replaces placeholders like $from etc in template
    ## with their Perl variable value equivalents
    my %replace = (
    from => "$from",
    recipients => "$recipients",
    name => "$name",
    target => "$target",
    diff => "$diff"
    );
    
    
    ##
    ## Adds device-specific recipients if configured
    ##
    if ( defined( $config->{'device'}->{$name}->{'notify'} ) ) {
        my $addNoticeTo = $config->{'device'}->{$name}->{'notify'};
        
        logEvent("Device Specific Notification Field Detected For $name");
        $recipients .= "," . $addNoticeTo;
        logEvent("Added $addNoticeTo To Global Notification List") if $VERBOSE;
    }
    
    ##
    ## Reads in mail template and safely replaces placeholder text
    ##
    open ( my $fh, '<', $template );
    my @msg = <$fh>;
    close $fh;
    
    foreach my $e (@msg) {
        for my $key ( keys %replace ) {
            $e =~ s/\$$key/$replace{$key}/g;
        }
        
    }
    
    ##
    ## Transmits message
    ##
    open ( my $mail, "|-", "$mailer") or logEvent("$!\n");
    print $mail @msg;
    close $mail;
    
    
    logEvent("Device $name Differential Notice sent to $recipients");
    logDiff($name,$diff) if $LOG_DIFFERENTIAL;
}

##
## Updates a state file with the last recieved configuration
##
sub updateStateFile() {
    my $name = $_[0];
    my $lastName = $_[1];
    my @state;
    
    logEvent("Reading State File $tracking/$name-state-file") if $VERBOSE;
    open IN, "<$tracking/$name-state-file" or return 0;
    while ( <IN> ) {
        chomp;
        push @state, $_;
    }
    close IN;
    
    my $size = @state;
    my $revisionDepth = $config->{'revision_depth'};
    
    if ( $size >= $revisionDepth ) {
        ## Remove the 'oldest' element in the array
        pop @state;
        ## Insert the newest configuration file into
        ## the beginning of the array
        logEvent("Adding $lastName to State File $name-state-file") if $VERBOSE;
        unshift @state, $lastName;
        
        ## If necessary, trim the array (ie if depth has changed)
        $#state = $config->{'revision_depth'} - 1;
        
        ## Update the state file
        unlink("$tracking/$name-state-file") or return 0;
        open OUT, ">$tracking/$name-state-file" or return 0;
        foreach my $line ( @state ) {
            print OUT "$line\n";
        }
        close OUT;
        return 1;
    } else {
        unshift @state, $lastName;
        
        ## Remove Duplicates
        my $prev = 'blank';
        my @cleanState = grep ($_ ne $prev && ($prev = $_), @state);
        
        
        open OUT, ">$tracking/$name-state-file" or return 0;
        foreach my $line ( @cleanState ) {
            print OUT "$line\n";
        }
        close OUT;
        return 1;
    }
    
    
    
    ##unlink("$tracking/$name-state-file") or return 0;
    ##createStateFile($name,$lastName) or return 0;
    return 0;
}

##
## Reads a state file and returns its contents
##
sub readStateFile() {
    my $name = $_[0];
    open IN, "<$tracking/$name-state-file" or return 0;
    my $state = <IN>;
    chomp $state;
    close IN;
    return $state;
}


##
## Creates a new state file for $name
##
sub createStateFile() {
    my $name = $_[0];
    my $last = $_[1];
    my $ok;
    
    logEvent("Creating state file $name with value $last");
    
    open OUT, ">$tracking/$name-state-file" or return 0;
    print OUT "$last\n";
    close OUT;
    
    return 1;
    
}

##
## Load XML configuration file
##
sub loadXMLConfig() {
    $config = XMLin( $configFile,  ) or die "$!";
    print "Parsed Configuration File $configFile\n";
}

##
## Set global variables
##
sub setGlobals() {

    $logFile = $config->{'logging'};
    $diffLog = $config->{'diff_log'};
    $tracking = $config->{'tracking'};
    $tftp = $config->{'tftp'}->{'address'};
    chomp($config->{'notification'}->{'notify-configuration-changes'});
    $config->{'notification'}->{'notify-configuration-changes'} =~ s/\n//g;

    ## Set Logging Globals from configuration
    $VERBOSE = $config->{'logging_verbose'};
    $VERBOSE = 0 if $config->{'logging_verbose'} =~ m/false|no|0/i;
    $LOG_DIFFERENTIAL = $config->{'log_differential'};
    $LOG_DIFFERENTIAL = 0 if $config->{'log_differential'} =~ m/false|no|0/i;
    $LOGGING = $config->{'logging_enabled'};
    $LOGGING = 0 if $config->{'logging_enabled'} =~ m/false|no|0/i;
    $numDevices = keys %{$config->{'device'}};

}

##
## Sanity Check Configuration
##
sub verifyConfiguration() {
    my $configErr = "ERROR -- ";
    my $errCount = 0;

    ## Resolves logical contradiction of enabled verbose but disabled logging
    if ( $VERBOSE and !$LOGGING ) {
        print "Disabling Verbose Logging because regular logging is disabled in $configFile\n";
        $config->{'logging'} = 1;    
    }

    ## Ensures Revision Depth is at least 1
    if ( ($config->{'revision_depth'} == 0) || !defined($config->{'revision_depth'}) ) {
        print "Revision depth is blank or 0 -- setting to 1\n";
        $config->{'revision_depth'} = 1;
    }

    ## Error if logging enabled with no log file specified
    if ( $LOGGING and !$config->{'logging'} ) {
	print "$configErr Logging Enabled but no logfile specified in $configFile\n"; 
        $errCount++;
    }

    ## Error if Differential loggign enabled but no log specified
    if ( !defined($diffLog) || ref($diffLog) eq "HASH" ) {
	print qq($configErr Diffential Logging enabled but no file specified -- check "<diff_log>" field in $configFile\n);
	$errCount++;
    }

    ## Error if no mail template field found
    unless ( $config->{'notification'}->{'mail-template'} ) {
        print "$configErr No Mail Template set in $configFile";
        $errCount++;
    }
    
    ## Error if Mail Template file not found
    unless (-e  $config->{'notification'}->{'mail-template'}) {
        print qq($configErr Configured Mail Template "$config->{'notification'}->{'mail-template'}" not found -- check "<mail-template>" field in $configFile\n);
        $errCount++;
    }   

    ## Error if configured tracking directory not found
    unless ( -e $tracking ) {
        print qq($configErr Configured Tracking Directory "$tracking" not found -- check "<tracking>" field in $configFile\n); 
        $errCount++;
    }

    ## Error if no notification recipient specified
    unless ( $config->{'notification'}->{'notify-configuration-changes'} ) {
        print "Blah = $config->->{'notification'}->{'notify-configuration-changes'}\n";
        print qq($configErr No notification address set, check field "<notify-configuration-changes>" in $configFile\n);
        $errCount++;
    }


   print "Please fix $errCount Errors in Configuration File -- Daemon Halted\n\n" if $errCount > 0;
   exit 1 if $errCount > 0;
}


##
## Subroutine uses SNMP to retrieve running-configuration
## from Cisco device via TFTP
##
sub getCiscoConfiguration {
    
    my $target = $_[0];
    my $community = $_[1];
    my $tftpServer = $_[2];
    my $name = $_[3];
    
    my $config = Cisco::CopyConfig->new(
    Host => $target,
    Comm => $community,
    Tmout => 2,
    Retry => 2
    );
    
    eval {
        
        if ( $config->copy($tftpServer, $name) ) {
            
            logEvent("getCiscoConfiguration: Successfully retrieved configuration for device $name") if $VERBOSE;
            
        } else {
            my $err = $config->error();
            logEvent("getCiscoConfiguration Error: $err");
            return 0;
        }
        
    };
    
    if ($@) {
        logEvent("WARNING Error Caught: $@") if @$;
        return 0;
    }
    
    return 1;
}

##
## Enable TFTP server on HP devices
##
sub enableHpTFTPServer() {
    ##
    ## HP OID to control TFTP Server
    ##
    ## .1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0
    ##
    ## Set to '1' to disable
    ## Set to '2' to enable
    ##
    
    my $address = $_[0];
    my $community = $_[1];
    my $OID = '.1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0';
    
    my ($session, $error) = Net::SNMP->session(
    -hostname       => $address,
    -version        => 'snmpv2',
    -community      => $community,
    -port           => 161
    );
    
    if ( !defined($session) ) {
        logEvent("enableHpTFTPServer Error Creating SNMP Session: $error");
        return 0;
    }
    
    my $result = $session->set_request(
    -varbindlist => [$OID, INTEGER, 2]
    );
    
    if ( !defined($result) ) {
        my $err = $session->error;
        logEvent("Device $address returned an SNMP error: $err");
        $session->close;
        return 0;
    }
    
    logEvent("Device $address TFTP Server enabled") if $VERBOSE;
    
    $session->close;
    
    return 1;
}

##
## Disable TFTP Server on HP devices
##
sub disableHpTFTPServer() {
    ##
    ## HP OID to control TFTP Server
    ##
    ## .1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0
    ##
    ## Set to '1' to disable
    ## Set to '2' to enable
    ##
    
    my $address = $_[0];
    my $community = $_[1];
    my $OID = '.1.3.6.1.4.1.11.2.14.11.5.1.7.1.5.6.0';
    
    my ($session, $error) = Net::SNMP->session(
    -hostname       => $address,
    -version        => 'snmpv2',
    -community      => $community,
    -port           => 161
    );
    
    if ( !defined($session) ) {
        logEvent("disableHpTFTPServer Error Creating SNMP Session: $error");
        return 0;
    }
    
    my $result = $session->set_request(
    -varbindlist => [$OID, INTEGER, 1]
    );
    
    if ( !defined($result) ) {
        my $err = $session->error;
        logEvent("Device $address returned an SNMP error: $err");
        $session->close;
        return 0;
    }
    
    logEvent("Device $address TFTP Server disabled") if $VERBOSE;
    
    $session->close;
    
    return 1;
}

##
## Create Empty Devices if less than 2 devices configured for monitoring
## (Data structures will not form correctly in this case)
##
sub createDummyDevices() {

    if ($numDevices == 0) {
        $config->{'device'}->{'name'} = "dummy2";
        $config->{'device'}->{'name'} = "dummy";
    }

    $config->{'device'}->{'name'} = "dummy" if $numDevices == 1;

}

##
## Daemonizes snmptastic.pl
##
sub daemonize() {
    chdir '/';
    open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    exit if $pid;
    setsid()                    or die "Can't start a new session: $!";
    umask 066;
    $RUNNING = 1;
    logEvent("$0 Daemonized");
}

##
## System log function
## Logs to file and location specified in "logging" field
## in snmptastic.conf
##
sub logEvent {
    my $message = $_[0];
    
    return unless $config->{'logging_enabled'};
    open OUT,">>$logFile" or die "Daemon Halted -- Error Writing to log $logFile: $!";
    printf OUT "%s %s\n",scalar localtime(),$message;
    close OUT;
}

##
## Differential Log function
## Logs differential notices to location specified
## in diff_log field in snmptastic.conf
##
sub logDiff {
    my $name = $_[0];
    my $diff = $_[1];
    my $time = scalar localtime;
    return unless $config->{'log_differential'};
    
    open OUT,">>$diffLog" or logEvent("No Differential Log File Specified! Configure in $1");
    
    printf OUT "%s ******** DIFFERENTIAL NOTICE FOR $name ********",scalar localtime;
    printf OUT "\nBEGIN CONFIGURATION CHANGE --------------------------------------------\n\n";
    printf OUT "$diff";
    printf OUT "\n\nEND CONFIGURATION CHANGE   --------------------------------------------\n\n";
    #printf OUT "%s ******** END OF NOTICE ************************\n",scalar localtime;
    
    close OUT;
    logEvent("Device $name Differential Notice logged to $diffLog");
    
}


##################################################################################
## END OF FILE
##################################################################################
