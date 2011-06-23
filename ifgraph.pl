#!/usr/bin/perl -w
#ifGraph 0.4.10 - Network Interface Data to RRD
#Copyright (C) 2001-2003 Ricardo Sartori
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
#Sugestoes e criticas (sem flames!!) mailto:sartori@ifgraph.lrv.ufsc.br
#Visite: http://ifgraph.lrv.ufsc.br

# Let's find out where we are
use FindBin;
# Found, now we add it to the @INC
use lib "$FindBin::Bin/lib";
# We are strict
use strict;
# Get the command line options
use Getopt::Std;
use vars qw($error $session $response $configfile $opt_T
	    $opt_l $opt_t $opt_c $opt_d $opt_h $opt_F);
getopt('cltF');
getopts('dhT');

# If the perl is older, we have to fetch the older Net::SNMP library
if ($] < 5.006) { 
	&debug("Warning: Older perl version $], we will use Net::SNMP 3.65\n");
	require Net::SNMP_365; 
} else {
	&debug("Starting ifgraph 0.4.10 with perl $], Net::SNMP 4.3\n");
	require Net::SNMP;
}

# SIGINT call
$SIG{INT}=\&sigint;

# HELP -h
if (defined($opt_h)) {
 print("\nifGraph 0.4.10 - Network Interface Data to RRD\nCopyright (C) 2001-2003 Ricardo Sartori\nhttp://ifgraph.lrv.ufsc.br/\n\nUsage: ./ifgraph.pl -c configfile [options], where options are:\n -d Turns on debugging\n -h This help text\n -l logfile Will log debug data to this file\n -t target1,target2,...,targetN Will collect data only for these targets (this is case insensitive)\n -F the number of child processes that must be created\n -T will use perl special var \$^T instead of N in rrdtool updates\n\n");
 exit(0);
}

# Defining the $configfile variable
if (defined($opt_c)) {
 $configfile=$opt_c;
} else {
 print("Warning: searching /usr/local/etc/, /etc and ./ for an ifgraph.conf file\n");
 if (-r "/usr/local/etc/ifgraph.conf") { 
  	$configfile="/usr/local/etc/ifgraph.conf";
 } elsif (-r "/etc/ifgraph.conf") { # used from the patch of Iain Lea <iain@bricbrac.de>
  	$configfile="/etc/ifgraph.conf";
 } elsif (-r "./ifgraph.conf") {
  	$configfile="./ifgraph.conf";
 } else {
  	die("main() Fatal: could not find an ifgraph.conf file. Use the -c option to point one\n");
 }
 print("main(): Found config file $configfile\n");
}

# Verify if the config file exists/readable/type
if (!(-r $configfile) || !(-f $configfile)) {
 die("main() Fatal: Could not read/find $configfile: ($!)\n");
} else {
 &debug("main(): Config file $configfile ok\n");
}

# $targets and $global are pointers to the configuration array
my($targets, $global)=&readconf($configfile);


# Verify the $opt_t flag
if (($opt_t) && ($opt_t ne "")) {
 &debug("main(): targets for this iteraction: $opt_t\n");
 ($targets,$global->[0])=&parseTargets;
} else {
 &debug("main(): no targets specified, fetching data from all\n");
}

# Verify if it can execute rrdtool ($global->[1])
if (!(-r $global->[1]) || !(-x $global->[1])) {
 die("main() Fatal: Could not execute/find rrdtool program at \"$global->[1]\" ($!)\nCheck the rrdtool directive in your config file\n");
} else {
 &debug("main(): Found rrdtool at $global->[1]\n");
}

# Verify if it can write/cd to the rrddir ($global->[2])
if (-d $global->[2]) {
 if ((-w $global->[2]) && (-x $global->[2])) {
  &debug("main(): Directory $global->[2] is ok\n");
 } else {
  die("main() Fatal: Could not read $global->[2] ($!)\nCheck directory permissions and your config file\n");
 }
} else {
 die("main() Fatal: It seems that $global->[2] is not a directory... check that out\n");
}

# Checks the -T flag
if ($opt_T) {
	$opt_T=$^T; # We update using the time the program started
} else {
	$opt_T="N"; # We update using the rrdtool N option
}

# Let's open a FH to rrdtool
if (open(RRDTOOL, "|$global->[1] -")) {
	&debug("main(): Opened the command \"$global->[1] -\" as FH RRDTOOL\n");
	select(RRDTOOL); $|=1; # autoflush for both
	select(STDOUT); $|=1;
} else {
	die("main() Fatal: Could not open filehandle RRDTOOL ($!)\n");
}

# re-set the $global->[4]
if (defined($opt_F) && ($opt_F =~ /\d+/)) { $global->[4]=$opt_F; }
if (defined($global->[4]) && ($global->[0] >= $global->[4]) && ($global->[4] > 1)) { # yes, we will fork
	my(@chandle);
	my($failcount)=0;
	&debug("main(): Starting the main loop ($global->[4] processes for $global->[0] targets)\n");
	my($deltaforks)=int(($global->[0]/$global->[4])+1); # yes, plus one, then we restrict the invalids
	for (my $fork=0; $fork < $global->[4]; $fork++) { # for each fork that must exist, do
		local *KID;
		my($first_target)=($fork*$deltaforks);
		my($kidpid);
	        do {
	            $kidpid=open(KID, "-|"); # it's a boy!!!
		    unless (defined $kidpid) {
			    print("main() Warning: cannot fork: $!\n");
			    if ($failcount++ > 6) { die("main() Fatal: Could not fork after $failcount attempts\n"); }
			    sleep 10;
		    }
	        } until defined $kidpid;
		if ($kidpid) { # I am the father, STDOUT is mine
		    $chandle[$fork]=*KID;
		    &debug("main(): Parent process $$ creating child pid $kidpid\n");
		} else { # I am just a little slave kid, my STDOUT goes to parent
		    for (my $ktarget=$first_target; 
		    $ktarget < ($first_target+$deltaforks) and $ktarget <= $global->[0]; 
		    $ktarget++) {
	 		&debug("main(): Starting scan for target $targets->[$ktarget][0] ($targets->[$ktarget][2]/$targets->[$ktarget][4]/$targets->[$ktarget][5])\n");
			if (($targets->[$ktarget][9] >= 60) && ($targets->[$ktarget][9] <= 345600)) {
				&debug("main(): valid heartbeat values\n");
			} else {
				print("Warning: Invalid heartbeat value ($targets->[$ktarget][9]) on target $targets->[$ktarget][0]. Using default=600\n");
				$targets->[$ktarget][9]=600;
			}
			&debug("KID $$ processing target $targets->[$ktarget][0] ($ktarget of ".($first_target+$deltaforks).")\n");
			if ($targets->[$ktarget][12] != 6) { 
				&snmpQuery($ktarget) || print("Warning: command snmpQuery() was not succesfully completed for target $targets->[$ktarget][0]\n");
			} else {
				&commandQuery($ktarget) || print("Warning: command commandQuery() was not succesfully completed for target $targets->[$ktarget][0]\n");
			}
		    } # end of for
		    exit(0); # we cannot forget (or misplace) this
		} # not a slave anymore, FREEDOM!!!
	} # end of for
	for (my $fork=0; $fork < $global->[4]; $fork++) {
		my($childhandle)=$chandle[$fork];
		my($output)="";
		while (<$childhandle>) {
			print $_;
		}
		close($childhandle);
	} # end of for
} else { # no, we are not going to fork
	&debug("main(): Starting the main loop (single-thread)\n");
	for (my $targetindex=0; $targetindex <= $global->[0]; $targetindex++) { # foreach target in the array
	         &debug("main(): Starting scan for target $targets->[$targetindex][0] ($targets->[$targetindex][2]/$targets->[$targetindex][4]/$targets->[$targetindex][5])\n");
	         if (($targets->[$targetindex][9] >= 60) && ($targets->[$targetindex][9] <= 345600)) {
	                 &debug("main(): valid heartbeat values\n");
	         } else {
	                 print("Warning: Invalid heartbeat value ($targets->[$targetindex][9]) on target $targets->[$targetindex][0]. Using default=600\n");
	                 $targets->[$targetindex][9]=600;
	         }
		 if ($targets->[$targetindex][12] != 6) {
			 &snmpQuery($targetindex) || print("Warning: command snmpQuery() was not succesfully completed for target $targets->[$targetindex][0]\n");
		 } else {
			 &commandQuery($targetindex) || print("Warning: command commandQuery() was not succesfully completed for target $targets->[$targetindex][0]\n");
		 }
	}
}
close(RRDTOOL);
&debug("main(): Exiting ifgraph\n");


sub commandQuery() {
	my($targetindex)=@_;
	# we must first execute the command and see the output, then we create the rrd files
	&debug("commandQuery(): Now we open a FileHandle to the command \"$targets->[$targetindex][5]\"\n");
	open(COMMANDFH ,"$targets->[$targetindex][5]|") || (print("commandQuery() Warning: Could not open a FileHandle to the command, jumping to next target\n") && return(0));
	my(@outputs);
	while (<COMMANDFH>) {
		chomp($_);
		$_ =~ s/ *//g;
		$outputs[$.-1]=$_;
		&debug("commandQuery(): reading output $. : $_\n");
	}
	close(COMMANDFH);
	&debug("commandQuery(): Starting fileCheckCommand($targets->[$targetindex][0])\n");
	$targets->[$targetindex][4]=$#outputs;
	$targets->[$targetindex][13]=&parseType($targets->[$targetindex][13]);
	&fileCheckCommand($targetindex) || (print("commandQuery() Warning: File creation/check for $targets->[$targetindex][0] unsucessfull, jumping to next target\n") && return(0));
	&insertCommandData($targetindex, @outputs);
	return(1);
}
	
	
############################################
# snmpQuery(): Gets the responses from the snmp agents and
# sends it to insertData function
# Arguments:
#  none
# Returns:
#  no return

sub snmpQuery {
  my($targetindex)=@_;
  &debug("snmpQuery(): Starting fileCheck($targets->[$targetindex][0])\n");
  if ($targets->[$targetindex][12] == 5) {
	  $targets->[$targetindex][13]=&parseType($targets->[$targetindex][13]);
	  &fileCheckOid($targetindex) || (print("snmpQuery() Warning: File creation/check for $targets->[$targetindex][0] unsucessfull, jumping to next target\n") || return(0)); # verifica os arquivos quando o target eh baseado em OIDs
  } else {
	  $targets->[$targetindex][13]="GAUGE";
          &fileCheckIf($targetindex) || (print("snmpQuery() Warning: File creation/check for $targets->[$targetindex][0] unsucessfull, jumping to next target\n") || return(0)); # funcao que verifica se o arquivo existe e o cria
  }
  &debug("snmpQuery(): Creating Net::SNMP session with $targets->[$targetindex][2] for interface/OID $targets->[$targetindex][5] (type $targets->[$targetindex][12]) on port $targets->[$targetindex][4]\n");
  # Iniciando uma sessao SNMP
  ($session, $error) = Net::SNMP->session(
     -hostname  =>  $targets->[$targetindex][2],
     -community =>  $targets->[$targetindex][3],
     -port      =>  $targets->[$targetindex][4],
     -timeout   =>  $targets->[$targetindex][8],
     -retries	=>  $targets->[$targetindex][6]
  );

  if (!defined($session)) {  # if session not defined
     print("snmpQuery() Warning: We got a Net::SNMP error -> $error\n");
     return(0);
  } else { # if it is defined
     &findInterfaceIndex($targetindex) || (print("snmpQuery() Warning: findInterfaceIndex did not return OK for target $targets->[$targetindex][0], jumping to next target\n") && return(0));
     &debug("snmpQuery(): Net::SNMP Session created... contacting agent on host\n");
     my(@oidstoget)=("1.3.6.1.2.1.2.2.1.8.$targets->[$targetindex][5]","1.3.6.1.2.1.2.2.1.10.$targets->[$targetindex][5]","1.3.6.1.2.1.2.2.1.14.$targets->[$targetindex][5]","1.3.6.1.2.1.2.2.1.16.$targets->[$targetindex][5]","1.3.6.1.2.1.2.2.1.20.$targets->[$targetindex][5]"); # this are the default OIDs
     if($targets->[$targetindex][12] == 5) {
	     @oidstoget=split(" *,",$targets->[$targetindex][5]);
	     for (my($i)=0; $i<=$#oidstoget; $i++) {
		     $oidstoget[$i]=~s/ *//g; # remove any blank
		     $oidstoget[$i]=~s/^\.?//g; # remove the initial dot
	     }
     }
     if (defined($response=$session->get_request(@oidstoget))) { # if we have a response
	if($targets->[$targetindex][12] == 5) { # if we got OID
		     my($tempoid)=0;
	             foreach $tempoid (@oidstoget) {
			my($data)=sprintf("%u", $response->{"$tempoid"});
			&insertOidData($data,$tempoid,$targetindex);
		     }
	} else { # if we got Interface
	             my($ocin)=sprintf("%u",$response->{"1.3.6.1.2.1.2.2.1.10.$targets->[$targetindex][5]"});
		     my($ocout)=sprintf("%u",$response->{"1.3.6.1.2.1.2.2.1.16.$targets->[$targetindex][5]"});
		     my($errin)=sprintf("%u",$response->{"1.3.6.1.2.1.2.2.1.14.$targets->[$targetindex][5]"});
		     my($errout)=sprintf("%u",$response->{"1.3.6.1.2.1.2.2.1.20.$targets->[$targetindex][5]"});
		    &insertIntData($ocin,$ocout,$errin,$errout,$targetindex);
	}
     } else { # negative response
        printf("snmpQuery() ERROR: %s for target $targets->[$targetindex][0]\n", $session->error());
	if($targets->[$targetindex][12] == 5) {
	            my($tempoid)=0;
		    foreach $tempoid (@oidstoget) {
			&insertOidDataNull($tempoid,$targetindex);
		    }
	} else {
		    &insertIntDataNull($targetindex);
	}
     }
  }
  $session->close();
  return(1);
}


#########################################
# findInterfaceIndex(): try to find the interface index of the target
# Arguments: 
#       none 
# Returns:
#       1 - if the interface index was found
#       0 - if the interface index could not be found

sub findInterfaceIndex {
	my($targetindex)=@_;
	if ($targets->[$targetindex][12] == 1) { # if the target has the interface number
		&debug("findInterfaceIndex(): we already have the index, we dont need to find it\n");
		return(1);
	} elsif ($targets->[$targetindex][12] == 5) { # if the target is an OID target
		&debug("findInterfaceIndex(): this is an OID target, we dont need to find the index\n");
		return(1);
	} else { # if the target is a mac, ip or name
		&debug("findInterfaceIndex(): We must have the interface index to go on\n");
		my $OIDIfIndexTable = "1.3.6.1.2.1.2.2.1.1"; # the interface index table
		# if there is no answer from the SNMP agent, prints a warning and sets the interface type to index
		# so it does not passes trough the &findIndexBy*() functions.
		if (defined($response=$session->get_table($OIDIfIndexTable))) { # we need the interface index to go on
			&debug("findInterfaceIndex(): the SNMP session is defined, lets go on with this\n");
			if ($targets->[$targetindex][12] == 2) {
				($targets->[$targetindex][5]=&findIndexByName) || return(0);
			} elsif ($targets->[$targetindex][12] == 3) {
				($targets->[$targetindex][5]=&findIndexByMac) || return(0);
			} elsif ($targets->[$targetindex][12] == 4) {
				($targets->[$targetindex][5]=&findIndexByIp) || return(0);
			}
		} else {
			print("findInterfaceIndex() Warning: could not get OIDIfIndexTable for target $targets->[$targetindex][0]: ", $session->error(),"\n");
			return(0);
		}
	}
}


###########################################
# fileCheckIf(): Checks if the apropriates rrd and log files are there,
# if they aren't, they are created
# Arguments:
#  none
# Returns:
#  no return

sub fileCheckIf {
  my($targetindex)=@_;
  # checking if the rrd files exists before starting a snmp session
  if (!-r "$global->[2]/$targets->[$targetindex][0].rrd") { # if the rrd file does not exist
        &debug("fileCheck(): file $global->[2]/$targets->[$targetindex][0].rrd does not exist\n");
  	&createRRD($targetindex) || (print("fileCheckIf() Warning: Could not create file $global->[2]/$targets->[$targetindex][0].rrd\n") && return(0));
  }
  # checking if the log file exists before a snmp session
  if (!-r "$global->[2]/$targets->[$targetindex][0].log") { # if the log file does not exist
  	&debug("fileCheck(): file $global->[2]/$targets->[$targetindex][0].log does not exist\n");
        &createLog($targetindex) || (print("fileCheckIf() Warning: Could not create file $global->[2]/$targets->[$targetindex][0].log\n") && return(0));
  }
  return(1);	
}

##########################################
# fileCheckCommand(): Checks if the apropriates rrd and log files are there,
# if they aren't, they are created
# Arguments:
#  none
# Returns:

sub fileCheckCommand {
	my($targetindex)=@_;
	#checking if the rrd files exists before starting to collect data
	if (!-r "$global->[2]/$targets->[$targetindex][0]") { # if the target directory does not exist
		&debug("fileCheck(): directory $global->[2]/$targets->[$targetindex][0] does not exist\n");
		mkdir("$global->[2]/$targets->[$targetindex][0]",0755) || (print("fileCheckCommand() Warning: Could not create directory $global->[2]/$targets->[$targetindex][0]: $!\n") && return(0));
	}
	#Let's check if the directory was created
	if ((-r "$global->[2]/$targets->[$targetindex][0]") && (-d "$global->[2]/$targets->[$targetindex][0]")) {
	        &debug("fileCheckCommand(): directory $global->[2]/$targets->[$targetindex][0] is OK\n");
	}
	# we need to check $targets->[$targetindex][4] rrd files
	my($i)=0;
	for ($i=0; $i <= $targets->[$targetindex][4]; $i++) {
		if (!-r "$global->[2]/$targets->[$targetindex][0]/data$i.rrd") { # if the data file with output $i isnt there
			&debug("fileCheckCommand(): file $global->[2]/$targets->[$targetindex][0]/data$i.rrd does not exists\n");
			&createRRDCommand($i,$targetindex) || (print("fileCheckCommand() Warning: createRRDCommand was not successfull\n") && return(0));
		}
		if (!-r "$global->[2]/$targets->[$targetindex][0]/data$i.log") { # if the data file with output $i isnt there
			&debug("fileCheckCommand(): file $global->[2]/$targets->[$targetindex][0]/data$i.log does not exists\n");
			&createLogCommand($i,$targetindex) || (print("fileCheckCommand() Warning: createLogCommand was not successfull\n") && return(0));
		}
	}
	return(1);
}

##########################################
# fileCheckOid(): Checks if the apropriates rrd and log files are there,
# if they aren't, they are created
# Arguments:
#  none
# Returns:
#  no return
#
sub fileCheckOid {
  my($targetindex)=@_;
  # checking if the rrd files exists before starting a snmp session
  if (!-r "$global->[2]/$targets->[$targetindex][0]") { # if the target directory does not exist
  	&debug("fileCheckOid(): directory $global->[2]/$targets->[$targetindex][0] does not exist\n");
        mkdir("$global->[2]/$targets->[$targetindex][0]",0755) || (print("fileCheckOid() Warning: Could not create directory $global->[2]/$targets->[$targetindex][0]: $!\n") && return(0));
  }
  # Let's check if the directory was created
  if ((-r "$global->[2]/$targets->[$targetindex][0]") && (-d "$global->[2]/$targets->[$targetindex][0]")) {
	  &debug("fileCheckOid(): directory $global->[2]/$targets->[$targetindex][0] is OK\n");
  }
  my(@temp_oids)=split(",", $targets->[$targetindex][5]);
  my($tempvar)="";
  foreach $tempvar (@temp_oids) {
          $tempvar=~s/ *//g; # remove any blank
          $tempvar=~s/^\.?//g; # remove the initial dot
	  if (!-r "$global->[2]/$targets->[$targetindex][0]/$tempvar.rrd") { # if the oid file does not exists
		  &debug("fileCheckOid(): file $global->[2]/$targets->[$targetindex][0]/$tempvar.rrd does not exists\n");
		  &createRRDOid($tempvar, $targetindex) || (print("fileCheckOid() Warning: createRRDOid was not succesfull\n") && return(0));
	  }
	  if (!-r "$global->[2]/$targets->[$targetindex][0]/$tempvar.log") { # if the oid file does no exists
		  &debug("fileCheckOid(): file $global->[2]/$targets->[$targetindex][0]/$tempvar.log does not exists\n");
		  &createLogOid($tempvar, $targetindex) || (print("fileCheckOid() Warning: createLogOid was not successfull\n") && return(0));
	  }
  }
  return(1);
}


#########################################
# insertOidData(): Checks if data and hbeat of files are OK and then UPDATES
# Arguments:
#  $data, $oid, $targetindex
# Returns:
#  0 on error
#  1 on OK

sub insertOidData {
	my($data, $oid, $targetindex)=@_;
	my($olddata, $hbeat);
	my($file)="$targets->[$targetindex][0]/$oid";
	if (open(RRDLOG, "$global->[2]/$file.log")) {
		&debug("insertOidData(): Log file $file.log opened OK\n");
		while (<RRDLOG>) { # Ler o arquivo de log
			/(\d+) (\d+)/; # /(data) (hbeat)/ 
			$olddata=$1; $hbeat=$2;
			($hbeat) || ($hbeat=1200);
		}
		close(RRDLOG);
	} else {
		$olddata=0; $hbeat=1200;
	}
	if ($targets->[$targetindex][9] != $hbeat) {
	        &debug("insertOidData(): hearbeats are not equal, tune RRD to $targets->[$targetindex][9]\n");
	        print(RRDTOOL "tune $global->[2]/$file.rrd -h oid:$targets->[$targetindex][9]\n") || print("insertOidData() Warning: Error on tunning file $file.rrd ($!)\n");
        } else {
                &debug("insertOidData(): heartbeats are OK\n");
        }
	if (($data < $olddata) && ($targets->[$targetindex][13] eq "COUNTER")) {
                &debug("insertOidData() Warning: System reboot? Counters reseted? Using (unknown)\n");
		&debug("insertOidData(): Actual in: $data < Old Data: $olddata\n");
		$data="U";
		&rrdLog($file, "0 $targets->[$targetindex][9]");
	} else {
		&rrdLog($file, "$data $targets->[$targetindex][9]");
	}
	&debug("insertOidData(): update $global->[2]/$file.rrd $opt_T:$data\n");
	print(RRDTOOL "update $global->[2]/$file.rrd $opt_T:$data\n") || (print("insertOidData() Warning: Error on updating file: $file.rrd ($!)\n") && return(0));
	return(1);
}


#########################################
# insertCommandData(): checks the outputs, checks the the log file for hbeat
# and then updates
# Arguments:
#  $targetindex, @returns
# Returns:
#  0 on error
#  1 on OK

sub insertCommandData {
	my($targetindex, @returns)=@_;
	&debug("insertCommandData(): processing from 0 to $#returns results\n");
	my($i)=0;
	for ($i=0; $i <= $#returns; $i++) {
		my($olddata,$hbeat);
		my($file)="$targets->[$targetindex][0]/data$i";
		if (open(RRDLOG, "$global->[2]/$file.log")) {
	                &debug("insertCommandData(): Log file $file.log opened OK\n");
	                while (<RRDLOG>) { # Ler o arquivo de log
	                        /(\d+) (\d+)/; # /(data) (hbeat)/
	                        $olddata=$1; $hbeat=$2;
	                        ($hbeat) || ($hbeat=1200);
	                }
		        close(RRDLOG);
		} else {
		        $olddata=0; $hbeat=1200;
		}
		&debug("insertCommandData(): processing result no $i ($returns[$i] < $olddata) -> $file.rrd\n");
		my($data)=$returns[$i];
		if (($data < $olddata) && ($targets->[$targetindex][13] eq "COUNTER")) {
			&debug("insertCommandData() Warning: System reboot? Counters reseted? Using (unknown)\n");
	                &debug("insertCommandData(): Actual in: $data < Old Data: $olddata\n");
	                $data="U";
			&rrdLog($file, "0 $targets->[$targetindex][9]");
		} else {
			&rrdLog($file, "$data $targets->[$targetindex][9]");
		}
		print(RRDTOOL "update $global->[2]/$file.rrd $opt_T:$data\n") || (print("insertCommandData() Warning: Error on updating file: $file.rrd ($!)\n") && return(0));
	}
	return(1);
}


########################################
# insertOidDataNull(): updates the oid rrd files with U (unknowns)
# Arguments:
#  $oid, $targetindex
# Returns:
#  0 on error
#  1 on OK

sub insertOidDataNull {
	my($oid, $targetindex)=@_;
	my($file)="$targets->[$targetindex][0]/$oid";
	&debug("insertOidDataNull(): update $global->[2]/$file.rrd $opt_T:U\n");
	print(RRDTOOL "update $global->[2]/$file.rrd $opt_T:U\n") || (print("insertOidDataNull() Warning: Error on updating file: $file.rrd ($!)\n") && return(0));
	&rrdLog($file, "0 $targets->[$targetindex][9]");
	return(1);
}

#######################################
# insertIntDataNull(): updates the interfaces rrd files with U (unknowns)
# Arguments:
#  $oid, $targetindex
# Returns:
#  0 on error
#  1 on OK
		
sub insertIntDataNull {
	my($targetindex)=@_;
	my($file)="$targets->[$targetindex][0]";
	&debug("insertIntDataNull: update $file.rrd $opt_T:0:0:0:0\n");
	print(RRDTOOL "update $global->[2]/$file.rrd $opt_T:U:U:U:U\n") || (print("insertIntDataNull() Warning: Error on updating file: $file.rrd ($!)\n") && return(0));
	&rrdIntLog($file,0,0,0,0,$targets->[$targetindex][9]);
	return(1);
}
			

############################################
# insertIntData(): Verify if data passed as argument is coerent to the RRD and
# check if the heartbeat is correct. If they arent, it will fix to make
# graphics look correct.
# Arguments:
#  none
# Returns:
#  no return

sub insertIntData {
   my($atualocin, $atualocout, $atualerrin, $atualerrout, $targetindex)=@_;
   my($oldocin, $oldocout, $olderrin, $olderrout, $hbeat);
   my($file)="$targets->[$targetindex][0]";
   if (open(RRDLOG, "$global->[2]/$file.log")) {
   	&debug("insertData(): Log file $file.log opened OK\n");
        while (<RRDLOG>) { # Ler o arquivo de log
		/(\d+) (\d+) (\d+) (\d+) (\d+)/ || /(\d+) (\d+) (\d+) (\d+)/; #(\d+)? didnt work
		$oldocin=$1; $oldocout=$2; $olderrin=$3; $olderrout=$4; $hbeat=$5;
		($hbeat) || ($hbeat=1200);
	}
   	close(RRDLOG);
   } else {
     	$oldocin=0; $oldocout=0; $olderrin=0; $olderrout=0; $hbeat=1200;
   }
   if ($targets->[$targetindex][9] != $hbeat) {
   	&debug("insertData(): hearbeats are not equal, tune RRD to $targets->[$targetindex][9]\n");
	print(RRDTOOL "tune $global->[2]/$file.rrd -h octetsin:$targets->[$targetindex][9] -h octetsout:$targets->[$targetindex][9] -h errorsin:$targets->[$targetindex][9] -h errorsout:$targets->[$targetindex][9]\n") || print("insertIntData() Warning: Error on tunning file $file.rrd ($!)\n");
   } else {
   	&debug("insertData(): heartbeats are OK\n");
   }
   &debug("insertData(): Data received ok... comparing\n");
   if (($atualocin < $oldocin) && ($atualocout < $oldocout)) {
		&debug("insertData() Warning: System reboot? Counters reseted? Using (unknown)\n");
 		&debug("insertData(): Actual in: $atualocin < Old Data: $oldocin\n");
		&log("InsereDados: actual < older ($atualocin < $oldocin) System reboot?\n");
		$atualocin="U";
		$atualocout="U";
		$atualerrin="U";
		$atualerrout="U";
		&rrdIntLog($file,0,0,0,0,$targets->[$targetindex][9]);
   } else {
		&debug("insertData() OK: Seems that counter is increasing. Using (actual)\n");
		&debug("insertData(): Actual data: $atualocin > Old Data: $oldocin\n");
		&log("InsereDados: actual > older ($atualocin>$oldocin) Normal update\n");
		&rrdIntLog($file,$atualocin,$atualocout,$atualerrin,$atualerrout,$targets->[$targetindex][9]);
   }
   &debug("insertData(): update $global->[2]/$file.rrd $opt_T:$atualocin:$atualocout:$atualerrin:$atualerrout\n");
   &log("Update $file.rrd $opt_T:$atualocin:$atualocout:$atualerrin:$atualerrout\n");
   print(RRDTOOL "update $global->[2]/$file.rrd $opt_T:$atualocin:$atualocout:$atualerrin:$atualerrout\n") || (print("insertIntData() Warning: Error on update $file.rrd: $!\n") && return(0));
   return(1);
}

############################################
# createRRD(): creates an RRD db for interface targets
# Arguments:
#  none
# Return:
#  0 - if file was not created
#  1 - if file was created

sub createRRD {
  my($targetindex)=@_;
  &debug("createRRD(): Creating SNMP type file for target $targets->[$targetindex][0]\n");
  system("$global->[1] create $global->[2]/$targets->[$targetindex][0].rrd -s $targets->[$targetindex][10] DS:octetsin:COUNTER:$targets->[$targetindex][9]:U:U DS:octetsout:COUNTER:$targets->[$targetindex][9]:U:U DS:errorsin:COUNTER:$targets->[$targetindex][9]:U:U DS:errorsout:COUNTER:$targets->[$targetindex][9]:U:U $targets->[$targetindex][11]\n")==0 || (print("createRRD(): Could not use system call ($!)\n") && return(0));
  if ((-r "$global->[2]/$targets->[$targetindex][0].rrd")==1) {
	&debug("createRRD(): File $global->[2]/$targets->[$targetindex][0].rrd created\n");
	return(1);
  } else {
	print("createRRD() Warning: Couldn't create $targets->[$targetindex][0].rrd ($!)\n");
 	return(0);
  }
}

###########################################
# createRRDOid(): creates an RRD db for OID targets
# Arguments:
#  none
# Return:
#  0 - if file was not created
#  1 - if file was created

sub createRRDOid {
	my($filename, $targetindex)=@_;
	&debug("createRRDOid(): Creating OID ($filename) type $targets->[$targetindex][13] file for target $targets->[$targetindex][0]\n");
	system("$global->[1] create $global->[2]/$targets->[$targetindex][0]/$filename.rrd -s $targets->[$targetindex][10] DS:oid:$targets->[$targetindex][13]:$targets->[$targetindex][9]:U:U $targets->[$targetindex][11]\n")==0 || print("createRRDOid(): Could not use system call ($!)\n");
	if ((-r "$global->[2]/$targets->[$targetindex][0]/$filename.rrd")==1) {
		&debug("createRRDOid(): File $global->[2]/$targets->[$targetindex][0]/$filename.rrd created\n");
		return(1);
	} else {
		print("createRRDOid() Warning: Couldn't create $targets->[$targetindex][0]/$filename.rrd ($!)\n");
		return(0);
	}
}

###########################################
# createRRDCommand(): creates an RRD db for command targets
# Arguments:
#  none
# Return:
#  0 - if file was not created
#  1 - if file was created

sub createRRDCommand {
	my($i,$targetindex)=@_;
	&debug("createRRDCommand(): Creating command type file for target $targets->[$targetindex][0]\n");
	system("$global->[1] create $global->[2]/$targets->[$targetindex][0]/data$i.rrd -s $targets->[$targetindex][10] DS:data:$targets->[$targetindex][13]:$targets->[$targetindex][9]:U:U $targets->[$targetindex][11]\n")==0 || print("createRRDCommand(): Could not use system call ($!)\n");
        if ((-r "$global->[2]/$targets->[$targetindex][0]/data$i.rrd")==1) {
                &debug("createRRDCommand(): File $global->[2]/$targets->[$targetindex][0]/data$i.rrd created\n");
                return(1);
        } else {
                print("createRRDCommand() Warning: Couldn't create $targets->[$targetindex][0]/data$i.rrd ($!)\n");
                return(0);
        }
}


############################################
# createLog(): creates an auxiliar log file for interface targets
# Arguments:
#  $file = the targets index
# Retorno:
#  0 - if file was not created
#  1 - if file was created

sub createLog {
 my($targetindex)=@_;
 open(RRDLOG ,">$global->[2]/$targets->[$targetindex][0].log") || die("createLog() Fatal: Error opening $global->[2]/$targets->[$targetindex][0].log ($!)\n");
 print(RRDLOG "0 0 0 0 $targets->[$targetindex][9]\n"); # in out errin errout heartbeat
 close(RRDLOG);
 if ((-r "$global->[2]/$targets->[$targetindex][0].log")==1) {
	&debug("createLog(): File $global->[2]/$targets->[$targetindex][0].log created\n");
	return(1);
 } else {
	&debug("createLog() ERROR: Couldn't create $targets->[$targetindex][0].lod ($!)\n");
 	return(0);
 }
}

###########################################
# createLogOid(): creates an auxiliar log file for Oid targets
# Arguments:
#  $file = the targets index
# Retorno:
#  0 - if file was not created
#  1 - if file was created

sub createLogOid {
	my($filename,$targetindex)=@_;
	open(RRDLOG ,">$global->[2]/$targets->[$targetindex][0]/$filename.log") || die("createLogOid Fatal: Error opening $global->[2]/$targets->[$targetindex][0]/$filename.log ($!)\n");
	print(RRDLOG "0 $targets->[$targetindex][9]\n"); # in out errin errout heartbeat
	close(RRDLOG);
	if ((-r "$global->[2]/$targets->[$targetindex][0]/$filename.log")==1) {
		&debug("createLogOid(): File $global->[2]/$targets->[$targetindex][0]/$filename.log created\n");
		return(1);
	} else {
		&debug("createLogOid() ERROR: Couldn't create $targets->[$targetindex][0]/$filename.log ($!)\n");
		return(0);
	}
}

###########################################
# createLogCommand(): creates an auxiliar log file for command targets
# Arguments:
#  $file = the targets index
# Retorno:
#  0 - if file was not created
#  1 - if file was created

sub createLogCommand {
	my($i,$targetindex)=@_;
	open(RRDLOG ,">$global->[2]/$targets->[$targetindex][0]/data$i.log") || die("createLogCommand() Fatal: Error opening $global->[2]/$targets->[$targetindex][0]/data$i.log ($!)\n");
	print(RRDLOG "0 $targets->[$targetindex][9]\n"); # data
	close(RRDLOG);
	if ((-r "$global->[2]/$targets->[$targetindex][0]/data$i.log")==1) {
		&debug("createLogCommand(): File $global->[2]/$targets->[$targetindex][0]/data$i.log created\n");
		return(1);
	} else {
		&debug("createLogCommand() ERROR: Couldn't create $targets->[$targetindex][0]/data$i.log ($!)\n");
		return(0);
	}
}



############################################
# log(): write debug data to a logfile
# Argumentos:
#  $arg - data to br written
# Retorn:
#  none

sub log  {
 my($arg)=@_;
 if ($opt_l) {
  open(LOGFILE ,">>$opt_l"); 
  print(LOGFILE time()." $arg");
  close(LOGFILE);
 }
}

############################################
# rrdIntlog(): write data to an auxiliar log file
# Arguments:
#  $file = the file to write
#  $ocin, $ocout, $errin, $errout = data processed in the insertData() call
#  $hbeat = the configured heartbeat
# Return:
#  none

sub rrdIntLog {
   my($file,$ocin,$ocout,$errin,$errout,$hbeat)=@_;
   open(RRDLOG, ">$global->[2]/$file.log") || die("rrdIntLog() Fatal: Error on opening log $global->[2]/$file.log ($!)\n");
   &debug("rrdIntLog(): $ocin,$ocout,$errin,$errout,$hbeat -> $file.log\n");
   print(RRDLOG "$ocin $ocout $errin $errout $hbeat\n");
   close(RRDLOG);
}

###########################################
# rrdLog(): write data to an auxiliar log file for command/OID targets
# Arguments:
#  $file = the file to write
#  $totaldata = data processed in the insert*Data() call (data hbeat)
#  
# Return:
#  none

sub rrdLog {
	my($file, $totaldata)=@_;
	open(RRDLOG, ">$global->[2]/$file.log") || die("rrdLog() Fatal: Error on opening log $global->[2]/$file.log ($!)\n");
	&debug("rrdLog(): \"$totaldata\" -> $file.log\n");
	print(RRDLOG "$totaldata\n");
	close(RRDLOG);
}

############################################
# debug(): print debug data to stdout
# Arguments:
#  $parm1 - data to be printed
# Return:
#  none

sub debug {
 if ($opt_d) {
  my($parm1)=@_;
  print($parm1);
 }
}


# I need to rewrite this... it begins to look confuse :)
# PERSONAL NOTE: THIS READCONF() IS NOT THE MAKEGRAPH READCONF().
############################################
# readconf(): read the config file and insert the apropriate values in the
# @global and @targets array
# Arguments:
#  $configfile = the configuration file
# Returns:
#  \@global, \@targets - pointers to the data collected

sub readconf  {
 my($configfile)=@_;
 my(@splited, @global, @targets, $target_name);
 # Setting targets defaults
 my(@default)=("name","1G","localhost","public",161,0,1,0,10,600,300,"RRA:AVERAGE:0.5:1:600 RRA:AVERAGE:0.5:6:700 RRA:AVERAGE:0.5:24:775 RRA:AVERAGE:0.5:288:797 RRA:MAX:0.5:1:600 RRA:MAX:0.5:6:700 RRA:MAX:0.5:24:775 RRA:MAX:0.5:288:797",0,"GAUGE");
 # Setting global defaults
 @global[1,2,4]=("/usr/local/bin/rrdtool","/usr/local/rrdfiles/",1);
 my($accept_new_target)=1;
 my($index)=-1; # $index replaces $global[0] during the parsing
 open(CONF,"$configfile") || die("readconf() Fatal: Could not read config file $configfile ($!)\n");
 while (<CONF>) {
  chomp($_); # remove o nl
  if (($_ =~ /^\[(.+)\] */) && ($_ !~ /^#.*/)) {  # se eh um [xxxx] e nao comeca com #
   $target_name=$1;		      # target recebe o que tem dentro do [ ]
   &debug("readconf(): Entering target: $target_name\n");
   if ($target_name ne "global") { # se o target nao eh o global
     if ($accept_new_target) { $index++ } else { $accept_new_target=1 } # increment the index number only if the target has
     									# a graph=true|yes or set the default for the next target
     $targets[$index]=[ @default ];
     $targets[$index][0]=$target_name;
   }
  }
  if (($_ =~ / *= */) && ($_ !~ /^#.*/)) { # se eh um campo = campo e nao comeca com #
   @splited=split(" *= *",$_);
   if (($splited[0] =~ /^ *$/) || ($splited[1] =~ /^ *$/)) { die("readconf() Fatal: Invalid data on line $. \"$_\"\n"); }
   if ($target_name eq "global") {
     if ($splited[0] =~ /rrdtool\Z/i) { $global[1]=$splited[1]; }
     elsif ($splited[0] =~ /rrddir\Z/i) { $global[2]=$splited[1]; }
     # we dont need to know where is the graphdir
     #elsif ($splited[0] =~ /graphdir/i) { $global[3]=$splited[1]; }
     elsif ($splited[0] =~ /forks\Z/i) { $global[4]=$splited[1]; }
     # setting the defaults
     elsif ($splited[0] =~ /max\Z/i) { $default[1]=$splited[1]; }
     elsif ($splited[0] =~ /host\Z/i) { $default[2]=$splited[1]; }
     elsif ($splited[0] =~ /community\Z/i) { $default[3]=$splited[1]; }
     elsif ($splited[0] =~ /port\Z/i) { $default[4]=$splited[1]; }
     elsif ($splited[0] =~ /interface\Z/i) { print("readconf() Warning: we *can not* use a default interface\n"); }
     elsif ($splited[0] =~ /interface_name\Z/i) { print("readconf() Warning: we *can not* use a default interface_name\n"); }
     elsif ($splited[0] =~ /interface_mac\Z/i) { print("readconf() Warning: we *can not* use a default interface_mac\n"); }
     elsif ($splited[0] =~ /interface_ip\Z/i) { print("readconf() Warning: we *can not* use a default interface_desc\n"); }
     elsif ($splited[0] =~ /oids\Z/i) { print("readconf() Warning: we *can not* use a default OID\n"); }
     elsif ($splited[0] =~ /command\Z/i) { print("readconf() Warning: we *can not* use a default command\n"); }
     elsif ($splited[0] =~ /retry\Z/i) { $default[6]=$splited[1]; }
     elsif ($splited[0] =~ /timeout\Z/i) { $default[8]=$splited[1]; }
     elsif ($splited[0] =~ /hbeat\Z/i) { $default[9]=$splited[1]; }
     elsif ($splited[0] =~ /step\Z/i) { $default[10]=$splited[1]; }
     elsif ($splited[0] =~ /rras\Z/i) { $default[11]=$splited[1]; }
     # jump to 13, 12 is used to define if interface is mac, ip, index or name
     elsif ($splited[0] =~ /type\Z/i) { $default[13]=$splited[1]; }
   } else {
     $targets[$index][0]=$target_name; 
     if ($splited[0] =~ /max/i) { $targets[$index][1]=$splited[1]; } # mandatory
     elsif ($splited[0] =~ /host\Z/i) { $targets[$index][2]=$splited[1]; } # optional
     elsif ($splited[0] =~ /community\Z/i) { $targets[$index][3]=$splited[1]; } #optional
     elsif ($splited[0] =~ /port\Z/i) { $targets[$index][4]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface\Z/i)  { $targets[$index][12]=1;  $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_name\Z/i)  { $targets[$index][12]=2; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_mac\Z/i)  { $targets[$index][12]=3; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_ip\Z/i)  { $targets[$index][12]=4; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /oids\Z/i) { $targets[$index][12]=5; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /command\Z/i) { $targets[$index][12]=6; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /timeout\Z/i) { $targets[$index][8]=$splited[1]; } # optional
     elsif ($splited[0] =~ /retry\Z/i) { $targets[$index][6]=$splited[1]; } # optional
     elsif ($splited[0] =~ /hbeat\Z/i) { $targets[$index][9]=$splited[1]; } # optional
     elsif ($splited[0] =~ /step\Z/i) { $targets[$index][10]=$splited[1]; } # optional
     elsif ($splited[0] =~ /rras\Z/i) { $targets[$index][11]=$splited[1]; } # optional
     # jump to 13, 12 is used to define if interface is mac, ip, index, name or OIDs
     elsif ($splited[0] =~ /type\Z/i) { $targets[$index][13]=$splited[1]; } # optional
     elsif ($splited[0] =~ /update\Z/i) { if ($splited[1] =~ /false|no/i) { $accept_new_target=0; } else { $accept_new_target=1; } }
   }
  }
 }
 close(CONF);
 $global[0]=$index;
 #&showTargets(\@targets,\@global);
 return(\@targets,\@global); # retorna os enderecos de memoria dos arrays lidos
}

###########################################
# showTargets(): shows the targets and their settings
# Arguments:
#  pointer to the targets and to the global arrays
# Returns:
#  0

sub showTargets {
	my($targets,$global)=@_;
	for (my($i)=0; $i <= $global->[0]; $i++) {
		print("Showing target #($i)\n");
		for (my($j)=0; $j <= 12; $j++) {
			print("[$targets->[$i][0]][$j]: $targets->[$i][$j]\n");
		}
	}
	exit(0);
}


############################################
# sigint(): close the snmp session if open
# Arguments:
#  none
# Returns:
#  0

sub sigint {
 print("Signal INT detected, cleaning up\n");
 &debug("sigint(): Config file is open, closing it\n");
 if (defined($session)) {
  &debug("sigint(): SNMP session open, closing it\n");
  $session->close();
 }
 exit(0);
}

############################################
# parseTargets(): creates a new target list containing only the targets
# that must be processed
# Arguments:
#  none
# Returns:
#  pointer to new_target and the new $global->[0]

sub parseTargets {
  my(@splited_opt)=split(",",$opt_t); # we get what target should be processed
  my(@new_target); # the new_target array
  my($counter_match)=-1; # should start in -1
  for (my($i)=0; $i <= $global->[0]; $i++) { # for all targets read
    #&debug("parseTargets(): $i\n"); 
    for (my($h)=0; $h <= $#splited_opt; $h++) { # for each target specified in the command line
 	&debug("parseTargets(): Comparing $targets->[$i][0] to $splited_opt[$h]\n");
 	if (lc($targets->[$i][0]) eq lc($splited_opt[$h])) {
		&debug("parseTargets(): MATCH\n");
		$counter_match++;
		$new_target[$counter_match]=$targets->[$i];
	}
    }
  }
  &debug("parseTargets(): Found ". ($counter_match+1) ." match(es)\n");
  return(\@new_target,$counter_match);
}

###########################################
# parseType(): checks what kind of RRD is to be build
# Arguments:
#  $temptype = the string
# Returns:
#  strings: GAUGE or DERIVE or ABSOLUTE or COUNTER


sub parseType {
	my($temptype)=@_;
	if ($temptype =~ / *gauge *| *derive *| *absolute *| *counter */i) {
		&debug("parseType(): Match on $temptype, returning uc($temptype)\n");
		return(uc($temptype));
	} else {
		&debug("parseType(): No Match, returning GAUGE\n");
		return("GAUGE");
	}
}

#########################################
# findIndexByName(): gets the interface index number by the name (description) of it
# Arguments: 
#       none
# Returns: 
#       the index of the interface if found, 0 if not found

sub findIndexByName {
	my($targetindex)=@_;
	my($nameresponse)="";
	&debug("findIndexByName(): Let's search for the name ($targets->[$targetindex][5])\n");
	my $OIDNameTable = '1.3.6.1.2.1.2.2.1.2';
	defined($nameresponse=$session->get_table($OIDNameTable)) || (print("findIndexByName() Warning: ", $session->error()) && return(0));
	foreach (&Net::SNMP::oid_lex_sort(keys(%{$response}))) {
		my($ifnum)=sprintf("%d", $response->{$_});
		my($name)=sprintf("%s", $nameresponse->{"$OIDNameTable.$ifnum"});
		if ($name =~ / *$targets->[$targetindex][5] */) {
			&debug("findIndexByName(): InterfaceName: $targets->[$targetindex][5] Index: $ifnum\n");
			return($ifnum);
		}
	}
	print("findIndexByName() Warning: Name ($targets->[$targetindex][5]) NOT found\n");
	return(0);
}

#########################################
# findIndexByMac(): gets the interface index number by it's MAC
# Arguments: 
#       none
# Returns: 
#       the index of the interface if found, 0 if not found

sub findIndexByMac {
	my($targetindex)=@_;
	my($macresponse)="";
	&debug("findIndexByMac(): Let's search for the mac address ($targets->[$targetindex][5])\n");
	my $OIDMacTable = '.1.3.6.1.2.1.2.2.1.6';
	defined($macresponse=$session->get_table($OIDMacTable)) || (print("findIndexByMac() Warning: ", $session->error()) && return(0));
	# ok, we have the responses, now let's clean the MAC mass
	if ($targets->[$targetindex][5] !~ /0x[a-z,0-9]{12}/i) { # if the mac is not in the SNMP default format 0xMAC
		$targets->[$targetindex][5] =~ s/://g;	# we remove the :
		$targets->[$targetindex][5] = "0x".$targets->[$targetindex][5]; # append a "0x" string on it
	} # now we have the default SNMP format MAC
	foreach (&Net::SNMP::oid_lex_sort(keys(%{$response}))) {
		my($ifnum)=sprintf("%d", $response->{$_});
		my($mac)=sprintf("%s", $macresponse->{"$OIDMacTable.$ifnum"});
		if ($mac =~ / *$targets->[$targetindex][5] */i) {
			&debug("findIndexByMac(): InterfaceMAC: $targets->[$targetindex][5] Index: $ifnum\n");
			return($ifnum);
		}
	}
	print("findIndexByMac() Warning: Mac ($targets->[$targetindex][5]) NOT found\n");
	return(0);
}


#######################################
# findIndexByIp(): gets the interface index number using it's IP
# Arguments: 
#       none
# Returns: 
#       the index of the interface if found, 0 if not found


sub findIndexByIp {
	my($targetindex)=@_;
        my($ipresponse)="";
        &debug("findIndexByIP(): Let's search for the ip address ($targets->[$targetindex][5])\n");
        my $OIDIPTable = '.1.3.6.1.2.1.4.20.1.2';
        defined($ipresponse=$session->get_table($OIDIPTable)) || (print("FindIndexByIp() Fatal: ", $session->error()) && return(0));
        if (defined($ipresponse->{"$OIDIPTable.$targets->[$targetindex][5]"})) { 
                my($ifnum)=sprintf("%s", $ipresponse->{"$OIDIPTable.$targets->[$targetindex][5]"});
                &debug("findIndexByIp(): InterfaceIP: $targets->[$targetindex][5] Index: $ifnum\n");
                return($ifnum);
        } else {
                print("findIndexByIp() Warning: Ip ($targets->[$targetindex][5]) NOT found\n");
                return(0);
        }
}
