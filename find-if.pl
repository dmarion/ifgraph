#!/usr/bin/perl -w
#ifGraph 0.4.10 - Network Interface Data to RRD
#Copyright (C) 2001-200333 Ricardo Sartori
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-
#
#Sugestoes e criticas (sem flames!!) mailto:sartori@lrv.ufsc.br
#Visite: http://ifgraph.lrv.ufsc.br

# Let's find out where we are
use FindBin;
# # Found, now we add it to the @INC
use lib "$FindBin::Bin/lib";
# # We are strict
use strict;
# # Get the command line options
use Getopt::Std;
getopts('adhims');

# We just nedd the basic features here
use Net::SNMP_365;

use vars qw($response $response2 $response3 $response4 $response5 $response6 $response7 $response8 $response9
	    $response10 $response11 $response12 $opt_d @ips $ip $mac $opt_a $opt_h $opt_m $opt_i $opt_s $if $desc $stat $ocin
	    $errin $ocout $errout);

# HELP
if (defined($opt_h)) {
	print("Usage: ./find-if.pl [-s] [-a] [-d] [-i] [-m] [[hostname] [[community] [[port]]]]\n hostname - the hostname/ip of the machine you will query (default: localhost)\n community - the community of the snmp agent (default: public)\n port - the port which the snmp agent is listening (default: 161)\n -a - Show all interfaces, even the ones that are down\n -d - Show some debug messages\n -i - Show the ip address associated with that interface\n -m - Shows the MAC address associated with each interface\n -s - Outputs target configs that can be added to the ifgraph.conf file\n find-if version 0.4.10 by Ricardo Sartori\n http://ifgaph.lrv.ufsc.br\n");
 exit(0);
}

# we need to set them if the opt_s is defined
my($hostname)=shift() || "localhost";
my($community)=shift() || "public";
my($port)=shift() || "161";

&debug("main(): Starting to create the Net::SNMP object\n");
my($session, $error) = Net::SNMP->session(
     -hostname  => $hostname,
     -community => $community,
     -port      => $port
);
 
if (!defined($session)) {
	printf("ERROR: %s.\n", $error);
	exit(0);
} else {
	print("OK: session created, getting info from ",$hostname,"\n");
	if ($opt_a) { 
		print("Showing all interfaces of: ",$hostname," \n");
	} else {
		print("Showing up interfaces of: ",$hostname," \n");
	} 
	my $OIDSystemDesc = '1.3.6.1.2.1.1.1.0';
	my $OIDSysUptime = '1.3.6.1.2.1.1.3.0';
	my $OIDtotalIf = '1.3.6.1.2.1.2.1.0';
	my $OIDDescricao = '1.3.6.1.2.1.2.2.1.2';
	my $OIDStatus = '1.3.6.1.2.1.2.2.1.8';
	my $OIDOctetsIn = '1.3.6.1.2.1.2.2.1.10';
	my $OIDErrorsIn = '1.3.6.1.2.1.2.2.1.14';
	my $OIDOctetsOut = '1.3.6.1.2.1.2.2.1.16';
	my $OIDErrorsOut = '1.3.6.1.2.1.2.2.1.20';
	my $OIDIfIndex = '1.3.6.1.2.1.2.2.1.1';
	my $OIDIpIndex = '.1.3.6.1.2.1.4.20.1.2'; 
	my $OIDMACIndex = '.1.3.6.1.2.1.2.2.1.6'; 
	my $OIDSpeedIndex = '.1.3.6.1.2.1.2.2.1.5';
	if (!defined($response = $session->get_request($OIDtotalIf))) {
		printf("ERROR: %s.\n", $session->error());
		$session->close();
		exit(1);
	} else {
		if ($opt_d) { $session->debug([0x02]); }
		print("Interface total: $response->{$OIDtotalIf}\n");
		print("OK: Collecting info on each interface, wait...\n");
		&debug("main(): Fetching table IfIndex\n");
		defined($response9=$session->get_table($OIDIfIndex)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfDesc\n");
		defined($response2=$session->get_table($OIDDescricao)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfStatus\n");
		defined($response3=$session->get_table($OIDStatus)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfOctetsIn\n");
		defined($response4=$session->get_table($OIDOctetsIn)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfErrorsIn\n");
		defined($response5=$session->get_table($OIDErrorsIn)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfOctetsOut\n");
		defined($response6=$session->get_table($OIDOctetsOut)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching table IfErrorsOut\n");
		defined($response7=$session->get_table($OIDErrorsOut)) || die("ERROR: ", $session->error());
		&debug("main(): Fetching objects SysDec, SysUptime\n");
		defined($response8=$session->get_request($OIDSystemDesc,$OIDSysUptime)) || die("ERROR: ", $session->error);
		if ($opt_i) {
			&debug("main(): Fetching table ipAdEntIfIndex\n");
			defined($response10=$session->get_table($OIDIpIndex)) || print("Warn: Could NOT get ipAdEntIfIndex table\n");
   		}
		if ($opt_m) {
			&debug("main(): Fetching table MAC\n");
			defined($response11=$session->get_table($OIDMACIndex)) || print("Warn: Could NOT get ifPhysAddress table\n");
   		}
		if ($opt_s) {
			&debug("main(): Fetching table MAXes\n");
			defined($response12=$session->get_table($OIDSpeedIndex)) || print("Warn: Could not get ifSpeed table\n");
		}
		print("OK: Data collected\n");
	}
	&debug("Viewing ip Adresses\n");
	if ($opt_i) {
		foreach (&Net::SNMP::oid_lex_sort(keys(%{$response10}))) {
	        	my($i)=sprintf("%s", $response10->{$_});
			$_ =~ s/\.1\.3\.6\.1\.2\.1\.4\.20\.1\.2\.//i;
	         	$ips[$i]=$_;
	  	}
  	}
	print("System Description: ", $response8->{$OIDSystemDesc},"\n");
	print("System Uptime: ",$response8->{$OIDSysUptime},"\n");
	($if, $desc, $stat, $ocin, $errin, $ocout, $errout, $ip, $mac)=("If #", "Description", "Stat", "Octets In", "Errors In", "Octets Out", "Errors Out", "IP Address", "MAC Address");
	$~="FORMAT_ORIG";
	if ($opt_m) { $~="FORMAT_MAC"; }
	if ($opt_i) { $~="FORMAT_IP"; }
	if (($opt_m) && ($opt_i)) { $~="FORMAT_MACIP"; }
  	write;
	($if, $desc, $stat, $ocin, $errin, $ocout, $errout, $ip, $mac)=("-------", "-----------", "----", "-------------", "---------", "-------------", "----------", "----------------", "---------------");
	write;
	foreach (&Net::SNMP::oid_lex_sort(keys(%{$response9}))) {
		my($i)=sprintf("%d", $response9->{$_});
	   	$if="($i)";
        	$desc=$response2->{"$OIDDescricao.$i"};
		$stat=$response3->{"$OIDStatus.$i"};
		if ($response4->{"$OIDOctetsIn.$i"}) { $ocin=sprintf("%u",$response4->{"$OIDOctetsIn.$i"}); } else { $ocin=0 }
		if ($response5->{"$OIDErrorsIn.$i"}) { $errin=sprintf("%u",$response5->{"$OIDErrorsIn.$i"}); } else { $errin=0 }
		if ($response6->{"$OIDOctetsOut.$i"}) { $ocout=sprintf("%u",$response6->{"$OIDOctetsOut.$i"}); } else { $ocout=0 }
		if ($response7->{"$OIDErrorsOut.$i"}) { $errout=sprintf("%u",$response7->{"$OIDErrorsOut.$i"}); } else { $errout=0 }
		if ($response11->{"$OIDMACIndex.$i"}) { $mac=&parseMac(sprintf("%s",$response11->{"$OIDMACIndex.$i"})); } else { $mac="not set" }
		if ($ips[$i]) { $ip=$ips[$i] } else { $ip = "not set" }
		if ($stat == 2) { $stat="down"; } else { $stat="up"; }
		if ($opt_a) { write; } else {
			if ($stat eq "up") { write } 
		}
	}
        if ($opt_s) {
		print("\n# Showing target configurations\n");
		foreach (&Net::SNMP::oid_lex_sort(keys(%{$response9}))) {
                	my($if)=sprintf("%d", $response9->{$_});
			my($ifdesc)=$response2->{"$OIDDescricao.$if"};
			my($speed)=$response12->{"$OIDSpeedIndex.$if"};
			if ($speed == 0) { $speed=1000000000 } # 1G
			print("# Target config for target $hostname ($ifdesc)
[$hostname-if$if]
hostname=$hostname
interface=$if
community=$community
port=$port
max=$speed\n");
		}
	}
	$session->close();
	exit(0);
}

format FORMAT_MACIP=
| @<<<<<< | @<<<<<<<<<< | @<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<<<<< | @<<<<<<<<<<<<<< |
$if, $desc, $stat, $ocin, $errin, $ocout, $errout, $ip, $mac
.

format FORMAT_MAC=
| @<<<<<< | @<<<<<<<<<< | @<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<<<< |
$if, $desc, $stat, $ocin, $errin, $ocout, $errout, $mac
.

format FORMAT_IP=
| @<<<<<< | @<<<<<<<<<< | @<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<<<<< |
$if, $desc, $stat, $ocin, $errin, $ocout, $errout, $ip
.

format FORMAT_ORIG=
| @<<<<<< | @<<<<<<<<<< | @<<< | @<<<<<<<<<<<< | @<<<<<< | @<<<<<<<<<<<< | @<<<<<< |
$if, $desc, $stat, $ocin, $errin, $ocout, $errout
.

sub debug {
 if ($opt_d) {
  my($parm1) = @_;
  print($parm1);
 }
}

sub parseMac {
	my($tempmac)=@_;
	if ($tempmac =~ /0x([a-z,0-9]{4})([a-z,0-9]{4})([a-z,0-9]{4})/i) {
		return("$1:$2:$3");
	} elsif ($tempmac =~ /([a-z,0-9]{2}):([a-z,0-9]{2}):([a-z,0-9]{2}):([a-z,0-9]{2}):([a-z,0-9]{2}):([a-z,0-9]{2})/i) { # This string - not hex string - is returned on Digitel Routers (http://www.digitel.com.br)
		return("$1$2:$3$4:$5$6");
	}
}
