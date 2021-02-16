# snmptastic

---++++ System Requirements

The requirements for snmpTastic are minimal; most any stock UNIX host should be acceptable. It was developed and deployed using vi, OpenBSD3.9, Perl 5.8.6, and Google.

*Requirements*

   * A UNIX host which has:
      * A locally available TFTP server and directory (or a remote TFTP server with it's directory mounted locally by NFS)
         * This TFTP server must be configured to 'create' files rather than requiring empty files to be available. This is typically done in =/etc/inetd.conf= as follows:
         * =tftp            dgram   udp     wait    root    /usr/libexec/tftpd      tftpd -cs /tftpboot=
         * UNIX =diff= or equivalent tool be available. The exact tool can be specified in the configuration file; be default, the daemon calls ='diff -wu'= to generate the data for differential emails. This is a stock tool and exists on most UNIX implementations.

   * Perl 5.8 or later
      * The following Perl Modules must be installed on the UNIX host which snmptastic is to be run on. Note these are all published and freely available CPAN modules.
         * Net::SNMP + Dependancies
         * Cisco::CopyConfig + Dependancies
         * XML::Simple + Dependancies
         * Net::TFTP
         * File::Copy (May be present in default Perl installation)
         * Data::Dumper (May be present in default Perl installation)
         
   * Relevent Cisco, Foundry, HP SNMP MIBS installed on the host server. Although these MIBS can be retrieved from the Internet, as a convenience a tarball of needed MIBS accompanies the snmpTastic distribution. This file should be extracted into the host server MIBS repository, Usually this location is =/usr/local/share/snmp/mibs=

   * The daemon uses TFTP to deliver Cisco configurations via SNMP; consequently the TFTP directory which configurations are delivered to must be locally available to snmptastic; either on a local file system, or mounted locally via NFS.

---++++ Installation

This installation walkthrough will suppose that the administrator is installing snmpTastic to: =/usr/local/snmpTastic=

   * Ensure the TFTP server on the destination UNIX host is configured as detailed in the Requirements section.
   * Extract the TAR file somewhere logical on the UNIX host:
      * =tar zxvf snmpTastic_1.0.tar.gz ; mv snmpTastic/ /usr/local=
   * Configure =snmptastic.conf= appropriately for your network. The sample file is fairly well documented.
      * It is not necessary for the configuration file to be in the same directory as the Perl daemon as the configuration is passed as a command line parameter during launch. One may safely move =snmptastic.conf= to =/etc= if so desired.
      * It is suggested the default =tracking= directory be used; this extracts into =snmpTastic/tracking= when the tarfile is unzipped. Any directory may be used however, so long as it is properly referenced in the configuration file.
   * Launch the daemon; this is done by calling =snmptastic.pl= and passing it the explicit path to the configuration file as the only command-line parameter. The syntax for this is:
      * =snmptastic.pl [configuration file]=
         * Example: =/usr/local/snmpTastic/snmptastic.pl /usr/local/snmpTastic/snmptastic.conf=

   * Verify the daemon is running by examining the log file. 


---++++ About snmpTastic

   * SnmpTastic was originally written in one day by Thor Newman during the fall of 2006. It was an attempt to provide a simple, secure, and reliable tool for Network Configuration Tracking. It was written to deliver an alternative to RANCID and was intended from the beginning to use SNMP and so avoid any simulated Terminal Sessions via Expect. Support for SSH to track UNIX host configuration changes was added later as the tool proved useful in production environments. 

   * The Original Developer, Thor Newman, conceived and developed this application to version 1.8. 

