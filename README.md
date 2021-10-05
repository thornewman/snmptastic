# SNMPTASTIC 1.9

************************************************************************************
INTRODUCTION
************************************************************************************

snmptastic is a production environment systems administration service for 
tracking network device and server configurations and logging and reporting 
configuration changes. It is useful for tracking and alerting on configuration changes 
across devices. 

When properly configured, it will run as a forked UNIX daemon, periodically retrieve
configuration files from configured devices, store them, log and send email 
notifications of differences in configurations over time.

It provides:
* A safe configuration history for devices it monitors
* Notifications whenever configuration changes occur

It uses SNMP as well as standard UNIX tools such as "diff", "sendmail", and "scp" to 
achieve this. It is an "old school" style of UNIX service. 

The requirements for snmptastic are minimal; most any stock UNIX host should be 
acceptable. It was originally developed and deployed using vi, OpenBSD3.9, Perl
5.8.6, and Google.
 

************************************************************************************
SECURITY BEST PRACTICES
************************************************************************************

Run snmptastic on a secure internal host with limited access only to appropriate
administrator.

The default configuration, if followed, is reasonably secure:

*  The tracking directory where configurations are stored only allows access by the 
   owning user

*  The script sets umask 066 as it daemonizes so configuration and state files have
   safe permissions

*  Network configurations themselves generally do not contain extremely sensitive
   Information like plain text passwords

*  The greatest security weakness is the plain-text SNMP v2 RW community string 
   required.  

   SNMP configuration on the monitored network devices should be configured with
   Access lists so the RW configuration is only usable from the host that
   snmptastic runs on. 

   The SNMP community string(s) used for snmptastic should be unique and not used 
   elsewhere.


************************************************************************************
REQUIREMENTS
************************************************************************************

A UNIX host which has:

* A locally available TFTP server and directory (or a remote TFTP server with its 
  directory mounted locally by NFS)
  
  This TFTP server must be configured to 'create' files rather than requiring empty 
  files to be available. 

  This is typically done in **/etc/inetd.conf** as follows:
  tftp dgram udp wait root **/usr/libexec/tftpd tftpd -cs /tftpboot**
  
  IT IS VERY IMPORTANT THIS BE DONE OR CONFIGURATION RETRIEVAL BY TFTP WILL FAIL

* UNIX "diff" or equivalent tool be available. 
  The exact tool, path, and parameters can be specified in the configuration file. 
  By default, the daemon calls "diff -wu" to generate the data for differential 
  emails. 
  
  This is a stock tool and exists on most UNIX implementations.

* Perl 5.8 or later
  The following Perl Modules must be installed on the UNIX host which snmptastic is 
  to be run on. Note these are all published and freely available CPAN modules.
         * Net::SNMP + Dependancies
         * Cisco::CopyConfig + Dependancies
         * XML::Simple + Dependancies
         * Net::TFTP
         * File::Copy (May be present in default Perl installation)
         * Data::Dumper (May be present in default Perl installation)
         
* Relevant Cisco, Foundry, HP SNMP MIBS installed on the host server. Although these 
  MIBS can be retrieved from the Internet, as a convenience a tarball of needed MIBS 
  accompanies the snmpTastic distribution. This file should be extracted into the 
  host server MIBS repository, Usually this location is /usr/local/share/snmp/mibs

* The daemon uses TFTP to deliver Cisco configurations via SNMP; consequently the 
  TFTP directory which configurations are delivered to must be locally available to 
  snmptastic.
  
  The directory path is configured in snmptastic.conf and must either be a local 
  file system, or mounted locally via NFS.

  The TFTP server must be configured with "-c" to allow new files to be created as
  files are transferred via TFTP.



************************************************************************************
PACKAGE INSTALLATION FILES
************************************************************************************

The installation tarball contains these files extracted into snmptastic/

snmptastic.pl		The executable. Will self daemonize. Terminate by sending 
                          it a kill signal. 

snmptastic.conf		Stock configuration file. It is self documented.

mibs.tar.gz		An archive of SNMP MIBS used by the script. Usually isn't 
                         needed to be installed.

mail.template		A template file used to create automatic email  
                         notifications, can be modified as desired

snmptastic.service	A systemd configuration that can be used to register 
                         snmptastic. Assumes installation to /opt/snmptastic, modify 
                         appropriately	

tracking/		An empty tracking directory which is the default for 
                         storing configurations and state files. This can be any 
                         directory, configured in snmptastic.conf

README			This file
		

************************************************************************************
INSTALLATION INSTRUCTIONS
************************************************************************************

This installation walkthrough will suppose that the administrator is installing 
snmpTastic to: /opt/snmptastic

* Ensure the TFTP server on the destination UNIX host is configured as detailed in 
  the Requirements section.

* Configure appropriate SNMP RW community string on Cisco, HP and Foundry Devices.
  Follow instructions in snmptastic.conf for device specific configurations. 

* Extract the TAR file somewhere logical on the UNIX host:

  tar zxvf snmptastic_1.9.tar.gz ; mv snmptastic/ /opt
   
* Configure snmptastic.conf appropriately for your network. The sample file is well 
  documented, contains all needed sections and device templates
  
  It is not necessary for the configuration file to be in the same directory as the 
  Perl daemon as the configuration is passed as a command line parameter during 
  launch. 
  
  One may safely move  snmptastic.conf to /etc if desired for example

* It is suggested the default tracking/ directory be used; this extracts into 
  snmptastic/tracking when the tarfile is unzipped. 
  
  Any directory may be used however, so long as it is properly referenced in the 
  configuration file.
  
  It is strongly advised the directory have strong permissions (0600) to protect the 
  contents

* Optional: Add to systemd
  Copy the snmptastic.service file to /usr/lib/systemd/system and register with 
  
  systemctl daemon-reload
  
  Make sure the path matches your actual installation directory -- the default is 
  /opt/snmptastic



************************************************************************************
STARTING AND STOPPING
************************************************************************************

* Regular Method 

  Run ./snmptastic.pl from the terminal passing it the explicit path to the 
  configuration file as the only command-line parameter.
  
  Example: ./snmptastic.pl snmptastic.conf
  Example: /opt/snmptastic.pl /opt/snmptastic/snmptastic.conf

  The program will launch and self-daemonize, logging to the log file specified in 
  snmptastic.conf (Default is /var/log/snmptastic.log)

  The daemon will cleanly shutdown if given a normal TERM kill signal

* SystemD Method

  Assuming you have properly installed it to systemd using the included 
  snmptastic.service file, control the daemon with systemctl

  systemctl status snmptastic
  systemctl start snmptastic
  systemctl stop snmptastic
  systemctl restart snmptastic

 
************************************************************************************
ABOUT SNMPTASTIC
************************************************************************************

Originally written in one day by Thor Newman during the fall of 2006. It was an 
attempt to provide a simple, secure, and reliable tool for Network Configuration 
Tracking using SNMP and was first created specifically for Cisco devices. 

Support for Foundry, HP, and then generic SCP to track UNIX or any other device
Which allows SSH-key based file retrieval by SCP.

Questions/Comments/Feedback Welcome to thornewman@icloud.com.

Current Version is 1.9.

************************************************************************************
LICENSE
************************************************************************************

snmptastic is copyright (c) Thor Newman. It is freeware and may be freely used and 
distributed. No charge may be levied for it licensing, distribution, or use and it 
remains the intellectual property of Thor Newman.
