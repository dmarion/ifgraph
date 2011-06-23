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

use FindBin;
use lib "$FindBin::Bin/lib";
use strict;
use Getopt::Std;
use Color::Rgb;
use vars qw($opt_d $opt_c $opt_B $opt_b $opt_h $opt_g $opt_t $opt_T $targetindex
	    $configfile $global $targets $response $randomic $session $error $rgb_converter);
use File::Copy;

getopt('ctT');
getopts('Bbgdh');

# If the perl is older, we have to fetch the older Net::SNMP library
if ($] < 5.006) { 
	&debug("Warning: Older perl version $], we will use Net::SNMP 3.65\n");
	require Net::SNMP_365; 
} else {
	&debug("Starting ifgraph 0.4.10 with perl $[, Net::SNMP 4.3\n");
	require Net::SNMP;
}

# HELP
if (defined($opt_h)) {
 printf("ifGraph 0.4.10 - Network Interface Data to RRD\nCopyright (C) 2001-2003 Ricardo Sartori\nhttp://ifgraph.lrv.ufsc.br/\n\nUsage: ./makegraph.pl -c configfile [options], where options are:\n -d Turns on debugging\n -h This help text\n -B use bytes instead of bits in the graphics\n -b use bits instead of bytes in the graphics (interface* targets)\n -g Graphics only. No HTML pages\n -t target1,target2,...,targetN Will collect data only for these targets\n -T templatedir Will use the template files in this directory\n\n");
 exit(0);
}

# Creating a color converter object
&debug("main(): Creating a RGB converter object from Color::Rgb\n");
$rgb_converter = new Color::Rgb(rgb_txt=>"$FindBin::Bin/lib/rgb.txt");
if ($rgb_converter) { &debug("main(): Ok RGB converter object created\n"); }

# Defining the $configile variable
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

# Checking if config file can be read/exists/kind
if (!(-r $configfile) || !(-f $configfile)) {
 die("main() Fatal: Could not read/find $configfile: ($!)\n");
} else {
 &debug("main(): Config file $configfile ok\n");
}

# Getting variables from readconf()
($targets,$global)=&readconf($configfile);

# Verify the $opt_t flag
if (($opt_t) && ($opt_t ne "")) {
	&debug("main(): targets for this iteraction: $opt_t\n");
	($targets,$global->[0])=&parseTargets($global);
} else {
	&debug("main(): no targets specified, fetching data from all\n");
}      

#Verify the $opt_T flag
if (($opt_T) && ($opt_T ne "")) {
 &debug("main(): template directory selected: $opt_T\n");
 $global->[4]=$opt_T;
} else {
 &debug("main(): using config file template: $global->[4]\n");
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


# Checking if I can write in graphdir ($global->[3])
if (-d $global->[3]) {
 if (-w $global->[3]) {
  &debug("Directory $global->[3] is ok\n");
 } else {
  die("main() Fatal: Could not write on $global->[3] ($!)\nFatal: Check directory permissions and your config file\n");
 }
} else {
 die("main() Fatal: It seems that $global->[3] is not a directory... check that out\n");
}

# Checking if I can read into templatedir ($global->[4])
if (-d $global->[4]) {
 if ((-r $global->[4]) && (-x $global->[4])) {
  &debug("main(): Directory $global->[4] is ok\n");
 } else {
  die("main() Fatal: Could not read $global->[4] ($!)\nCheck directory permissions and your config file\n");
 }
} else {
 die("main() Fatal: It seems that $global->[4] is not a directory... check that out\n");
}

# Let's open a FH to rrdtool
if (open(RRDTOOL, "|$global->[1] -")) {
	&debug("main(): Opened the command \"$global->[1] -\" as FH RRDTOOL\n");
	select(RRDTOOL); $|=1;
	select(STDOUT); $|=1;
} else {
	die("main() Fatal: Could not open RRDTOOL ($!)\n");
}

# if (-g) == true then I will not create HTML
if (!($opt_g)) { 
	srand(time());   # a seed
	$randomic=rand(100000); # the random number created
	&createTemplateIndex();
}

# Parsing global[5] to set the image format
if ($$global[5]) {
	&debug("main(): Parsing the image format ($$global[5])\n");
	if ($$global[5] =~ /GD|PNG|GIF/i) { 
		&debug("main(): GD or PNG or GIF\n");
		$$global[5]=uc($$global[5]);
		if ($$global[5] eq "IGIF") { 
			&debug("main(): Adding the --interlace flag\n"); 
			$$global[5]="GIF --interlace";
		}
	} else {
		&debug("main(): Using default PNG\n");
		$$global[5]="PNG"
	}
}

	
# Starting the main loop
&debug("main(): Starting the loop process\n");
for ($targetindex=0; $targetindex <= $global->[0]; $targetindex++) { # for each valid target
  	&debug("main(): Starting scan for target $targets->[$targetindex][0] ($targets->[$targetindex][2]/$targets->[$targetindex][4]/$targets->[$targetindex][5])\n");
	if (&reconfigureTarget) { 
	   if ($targets->[$targetindex][17] != 6) { 
		&snmpQuery || print("Warning: command snmpQuery() was not succesfully completed for target $targets->[$targetindex][0]\n"); 
	   } else {
		&commandQuery || print("Warning: command commandQuery() was not succesfully completed for target $targets->[$targetindex][0]\n");
	   }
	 } else {
	   print("Warning: command reconfigureTarget was not successfully completed for target $targets->[$targetindex][0]\n"); # this reconfigures the target according to it's options and definitions
	 }
}
if (!($opt_g)) { 
       &closeTemplateIndex;    
}
close(RRDTOOL);
&debug("main(): Exiting makegraph\n");


############################################
# reconfigureTarget(): Gets the options and definitions of the target and processes it, so the
# rest of the program can understand them
# Arguments:
#  none
# Returns:
# 0 - When there is an error
# 1 - if ok

sub reconfigureTarget {
  my($targetsindex)=@_;
  $targets->[$targetindex][1]=&parseMaxes($targets->[$targetindex][1]); # analise maxes and reconfigure
  $targets->[$targetindex][6]=&parseOptions($targets->[$targetindex][6]); # analise options and reconfigure
  $targets->[$targetindex][7]=&parseDimensions($targets->[$targetindex][7]); # analise dimensions and reconfigure
  $targets->[$targetindex][8]=&parseColors($targets->[$targetindex][8]); # analise colors and reconfigure
  $targets->[$targetindex][10]=&parseTitle($targets->[$targetindex][10]); # analise and reconfigure title
  $targets->[$targetindex][20]=&parsePrecision($targets->[$targetindex][20]); # analise and reconfigure precision
  if ($targets->[$targetindex][17] == 5) { # if we are creating an OID graphic
	$targets->[$targetindex][18]=&createOidDefs($targets->[$targetindex][5],$targets->[$targetindex][18],$targets->[$targetindex][11]);    # then we parse and create the definitions
	($targets->[$targetindex][18]) || (print("reconfigureTarget() Warning: createOidDefs did not return OK\n") && return(0));
  } elsif ($targets->[$targetindex][17] == 6) {
	#print("createCommandDefs($targets->[$targetindex][18],$targets->[$targetindex][11]);\n");
	$targets->[$targetindex][18]=&createCommandDefs($targets->[$targetindex][18],$targets->[$targetindex][11]);  # parsing and creating command definitions
	($targets->[$targetindex][18]) || (print("reconfigureTarget() Warning: createCommandDefs did not return OK\n") && return(0));
  } else { # if NOT creating OID/Command graphics, we must set the Legends
	$targets->[$targetindex][11]=&parseLegends($targets->[$targetindex][11]);  # not OID? we must reconfigure the legends
  }
  $targets->[$targetindex][16]=~s/ *//g; # analise periods and reconfigure
  return(1);
}
						       


############################################
# snmpGetInfo(): Gets the information from the snmp agents (contact, uptime, desc, location,
# name, sysdesc)
# Arguments:
#  none
# Returns:
#  pointer to the responde -> if can fetch
#  0 -> if was not able to get the information

sub snmpGetInfo {
	# Defining the OIDs to get
	my $OIDDescricao = "1.3.6.1.2.1.2.2.1.2.$targets->[$targetindex][5]";
        if ($targets->[$targetindex][17] == 5) { $OIDDescricao = '1.3.6.1.2.1.1.1.0'; }
	my $OIDSystemDesc = '1.3.6.1.2.1.1.1.0';
	my $OIDSysUptime = '1.3.6.1.2.1.1.3.0';
	my $OIDSysContact = '1.3.6.1.2.1.1.4.0';
	my $OIDSysLocation = '1.3.6.1.2.1.1.6.0';
	my $OIDSysName = '1.3.6.1.2.1.1.5.0';
	if (defined($response=$session->get_request($OIDDescricao,$OIDSystemDesc,$OIDSysUptime,$OIDSysContact,$OIDSysLocation,$OIDSysName))) {
		&debug("snmpGetInfo(): Information from agent fetched ($response)\n");
		return(\$response);
	} else {
		&debug("snmpGetInfo() Warning: we could not get SNMP information from target $targets->[$targetindex][0]\n");
		return(\0);
	}
}


###########################################
# snmpQuery(): Gets the responses from the snmp agents and
# calls the organizaGraficos function
# Arguments:
#  none
# Returns:
#  0 on Net::SNMP Error
#  1 on everything else

sub snmpQuery {
  # Starting the SNMP Session
  &debug("snmpQuery(): Creating Net::SNMP session with $targets->[$targetindex][2] for interface/OID $targets->[$targetindex][5] ($targets->[$targetindex][17]) on port $targets->[$targetindex][4]\n");
  ($session, $error) = Net::SNMP->session(
     -hostname  =>  $targets->[$targetindex][2],
     -community =>  $targets->[$targetindex][3],
     -port      =>  $targets->[$targetindex][4],
     -retries   =>  $targets->[$targetindex][14],
     -timeout   =>  $targets->[$targetindex][15]
  );
  if (!defined($session)) {  # if session isnt defined, show an error
     print("snmpQuery() Warning: We got a Net::SNMP error -> $error\n");
     return(0);
  } else { # if the Net::SNMP session is defined
     &findInterfaceIndex || print("snmpQuery() Warning: findInterfaceIndex did not return OK for target $targets->[$targetindex][0]\n");
     if (!($opt_g)) { # if HTML is wanted
	my($ptr_response)=\0; # the default value is null
	if ($targets->[$targetindex][6][4] == 1) { # options=info defined (default) 
	     &debug("snmpQuery(): Yes, we want agent information, calling snmpGetInfo()\n");
	     $ptr_response=&snmpGetInfo;
     	} else {
	     &debug("snmpQuery(): No, we do not want agent information (options=noinfo)\n");
	}
	&debug("snmpQuery(): Calling addTemplate*($$ptr_response)\n");
	&addTemplateInterface($ptr_response);
	&addTemplateIndex($ptr_response);
     }
     &organizaGraficos; # sending data to rrdtool
     $session->close(); # we close the session that was opened
  }
  return(1); # now return true
}

##########################################
# commandQuery(): Gets the responses from the commands
# Arguments:
#  none
# Returns:
#  1 on anything 

sub commandQuery {
	#Starting to process the command
	&debug("commandQuery(): Creating command graphics for $targets->[$targetindex][2] calling \"$targets->[$targetindex][5]\"\n");
	if (!($opt_g)) { # if HTML is wanted
		my($ptr_response)=\0; # the default value is null
		&debug("commandQuery(): Calling addTemplate*($$ptr_response)\n");
		&addTemplateInterface($ptr_response);
		&addTemplateIndex($ptr_response);
	}
	&debug("commandQuery(): my kilo is $targets->[$targetindex][12]\n");
	&organizaGraficos; # sending data to rrdtool
	return(1); # now return true
}
	  


###########################################
# parseMaxes(): Gets the description of the bandwidth from the
# confifile and makes it computable
# Arguments:
#  $string_max = the maxes
# Returns:
#  pointer to @maxes, an array with de definitions of maxes

sub parseMaxes {
 my($string_max)=@_;
 my(@maxes,$tempmax);
 my($i)=0;
 my(@splited_maxes)=split("/",$string_max);
 while ($tempmax=shift(@splited_maxes)) {
	my($quant,$mult)=(0,1);
	if (($tempmax =~ /([0-9,\.]+) *([G,g,M,m,K,k]?)/)) { # max
		$quant=$1; 
		# if the mult is not defined, it is = 1
		if (defined($2) && ($2 ne "")) { $mult=$2; } else { $mult=1; } # the value and the mult
		if ($quant == 0) { $quant=1; $mult="G" } # redefining if defined with 0
		my($kilo)=1000;
		# redefining the value of 1k
		if ($targets->[$targetindex][17] >= 5) { 
			&debug("parseMaxes(): our kilo is $targets->[$targetindex][12] for target OID\n");
			$kilo=$targets->[$targetindex][12]; 
		}
                &debug("parseMaxes(): Searching for valid bandwidth descriptions: $quant ($mult)\n");
                &debug("parseMaxes(): value: $quant multiple: $mult kilo: $kilo\n");
		if ($mult =~ /^[G,g]$/) { $mult=$kilo*$kilo*$kilo };
		if ($mult =~ /^[M,m]$/) { $mult=$kilo*$kilo };
		if ($mult =~ /^[K,k]$/) { $mult=$kilo };
		$maxes[$i] = $quant*$mult;
		&debug("parseMaxes(): Total[$i]: $maxes[$i]\n");
		$i++;
	}
 }
 # returning the array
 return(\@maxes);
}


##########################################
# createOidDefs(): gets the string of oids, the definitions and the legends and builds
# the corrects DEFs to be used by rrdtool
# Arguments:
#  $string_oids = the oids
#  $string_defs = the oids definitions
#  $string_legends = the legends
# Returns:
#  $definition_string = the string used by rrdtool

sub createOidDefs {
	my($string_oids,$string_defs,$string_legends)=@_;
	my($definition_string,$gprint_string)=("","");
	&debug("createOidDefs(): $string_oids / $string_defs / $string_legends\n");
	my(@oids)=split(",",$string_oids); # now we have an array with oids
	my(@legends)=split(",",$string_legends); # now we have an array with legends
	my(@splited_defs)=split(",",$string_defs); # now we have the definitions
	if ($#oids != $#legends) { print("createOidDefs() Warning: you defined ",$#oids+1," OIDs and ",$#legends+1," legends. You must fix it or no graphic will be created.\n"); return(0); }
	elsif ($#oids != $#splited_defs) { print("createOidDefs() Warning: you defined ",$#oids+1," OIDs and ",$#splited_defs+1,"oiddefs. You must fix it or no graphic will be created.\n"); return(0); }
	my($dottedoid)=""; my($i)=0;
	while ($dottedoid=shift(@oids)) { # we got a single OID
		my($oiddef) = $splited_defs[$i];
		my($oiddeftype,$oiddefcolor)=("LINE2","#CCAADD");
		if ($oiddef =~ /(LINE1|LINE2|LINE3|AREA|STACK)(#[0-9,A-F]{6})\Z/i) { # the hexa definition
			($oiddeftype,$oiddefcolor)=($1,$2); # now we have the oid, the striped oid, the def and the color
		} elsif ($oiddef =~ /(LINE1|LINE2|LINE3|AREA|STACK)\$(.+)\Z/i) { # the rgb string definition
	                ($oiddeftype,$oiddefcolor)=($1,($rgb_converter->hex("$2",'#') || "CCAADD"));
		} else {
			print("createOiDefs() Warning: Seems to be an error on OID definition \"$oiddef\" on target $targets->[$targetindex][0], will use default LINE2#CCAADD\n");
		}
		# Lets get it all together
		# 
		$dottedoid=~s/^\.?//g; # remove the initial dot
		$definition_string=$definition_string."DEF:oid$i=$global->[2]/$targets->[$targetindex][0]/$dottedoid.rrd:oid:AVERAGE $oiddeftype:oid$i"."$oiddefcolor:\"$legends[$i]\" ";
		$gprint_string=$gprint_string."GPRINT:oid$i:LAST:\'$legends[$i] - Now\\: %.2lf $targets->[$targetindex][13]\' GPRINT:oid$i:AVERAGE:\'Average\\: %.2lf $targets->[$targetindex][13]\' GPRINT:oid$i:MAX:\'Max\\: %.2lf $targets->[$targetindex][13]\' COMMENT:\\l ";
		$i++;
			
	}
	#joining them
	$definition_string=$definition_string . "COMMENT:\\l " . $gprint_string;
	return($definition_string);
}

sub createCommandDefs {
	my($string_defs,$string_legends)=@_;
	my($definition_string,$gprint_string)=("","");
	&debug("createCommandDefs(): ($string_defs)/($string_legends)\n");
	my(@legends)=split(",",$string_legends); # now we have an array with legends
	my(@splited_defs)=split(",",$string_defs); # now we have the definitions
	if ($#splited_defs != $#legends) { 
		print("createCommandDefs() Warning: you defined ",$#splited_defs+1," Definitions and ",$#legends+1," legends. You must fix it or no graphic will be created.\n"); return(0); 
	}
	my($i)=0;
	for ($i=0; $i <= $#splited_defs; $i++) { # we got a single Data index
		my($commanddef) = $splited_defs[$i];
		my($commanddeftype,$commanddefcolor)=("LINE2","#CCAADD");
		if ($commanddef =~ /(LINE1|LINE2|LINE3|AREA|STACK)(#[0-9,A-F]{6})\Z/i) { # the hexa definition
			($commanddeftype,$commanddefcolor)=($1,$2); # now we have the Data index, the def and the color
		} elsif ($commanddef =~ /(LINE1|LINE2|LINE3|AREA|STACK)\$(.+)\Z/i) { # the rgb string definition
			($commanddeftype,$commanddefcolor)=($1,($rgb_converter->hex("$2",'#') || "CCAADD"));
		} else {
			print("createCommandDefs() Warning: Seems to be an error on Command definition \"$commanddef\" on target $targets->[$targetindex][0], will use default LINE2#CCAADD\n");
		}
		# Lets get it all together
		$definition_string=$definition_string."DEF:data$i=$global->[2]/$targets->[$targetindex][0]/data$i.rrd:data:AVERAGE $commanddeftype:data$i"."$commanddefcolor:\"$legends[$i]\" ";
		$gprint_string=$gprint_string."GPRINT:data$i:LAST:\'$legends[$i] - Now\\: %.2lf $targets->[$targetindex][13]\' GPRINT:data$i:AVERAGE:\'Average\\: %.2lf $targets->[$targetindex][13]\' GPRINT:data$i:MAX:\'Max\\: %.2lf $targets->[$targetindex][13]\' COMMENT:\\l ";
	}
	#joining them
	$definition_string=$definition_string . "COMMENT:\\l " . $gprint_string;
	return($definition_string);
}


##########################################
# parseOptions(): sets an array of 0 and 1 according to the options
# defined by the user
# Arguments:
#  $totaloptions = the string that contain the options in human format
# Returns:
#  pointer to @opcoes, the array with the options turned off (0) or on (1)

sub parseOptions {
  my(@opcoes)=(1,-1,-1,1,1,0,0,1,0);
  my($totaloptions)=@_;
  my(@splited)=split(",",$totaloptions);
  for (my($i)=0; $i < scalar(@splited); $i++) {
    if ($splited[$i] =~ /\A *noerror *\Z/i) { $opcoes[0]=-1 }
    elsif ($splited[$i] =~ /\A *error *\Z/i) { $opcoes[0]=1 }
    elsif ($splited[$i] =~ /\A *noinvert *\Z/i)  { $opcoes[1]=-1 }
    elsif ($splited[$i] =~ /\A *invert *\Z/i)  { $opcoes[1]=1 }
    elsif ($splited[$i] =~ /\A *norigid *\Z/i) { $opcoes[2]=-1 }
    elsif ($splited[$i] =~ /\A *rigid *\Z/i) { $opcoes[2]=1 }
    elsif ($splited[$i] =~ /\A *nolegend *\Z/i) { $opcoes[3]=-1 }
    elsif ($splited[$i] =~ /\A *legend *\Z/i) { $opcoes[3]=1 }
    elsif ($splited[$i] =~ /\A *noinfo *\Z/i) { $opcoes[4]=-1 }
    elsif ($splited[$i] =~ /\A *info *\Z/i) { $opcoes[4]=1 }
    elsif ($splited[$i] =~ /\A *bytes *\Z/i) { $opcoes[5]=1 }
    elsif ($splited[$i] =~ /\A *bits *\Z/i) { $opcoes[5]=0 }
    #elsif ($splited[$i] =~ /\A *graph *\Z/i) { $opcoes[6]=1 }
    #elsif ($splited[$i] =~ /\A *nograph *\Z/i) { $opcoes[6]=-1 }
    elsif ($splited[$i] =~ /\A *minorgrid *\Z/i) { $opcoes[7]=1 }
    elsif ($splited[$i] =~ /\A *nominorgrid *\Z/i) { $opcoes[7]=-1 }
    elsif ($splited[$i] =~ /\A *altautoscale *\Z/i) { $opcoes[8]=-1 }
  }
  return(\@opcoes);
}

#########################################
# parseLegends(): set a 2 string array containing the data specified by the user
# Arguments:
#  $string_legend = the string that contain the legends separated by commas
# Returns:
#  pointer to @legends


sub parseLegends {
	  my(@legends)=("Data In","Data Out");
	  my($string_legend)=@_;
	  my(@splited)=split(",",$string_legend);
	  if (defined($splited[0])) { $legends[0]=$splited[0]; }
	  if (defined($splited[1])) { $legends[1]=$splited[1]; }
	  return(\@legends);
}


########################################
# parseTitle(): substitutes localtime vars in the title
# Arguments:
#  $title = the title configured in the ifgraph.conf file
# Returns:
#  the title reconfigured


sub parseTitle {
	my($title)=@_;
	my($sec,$min,$hour,$day,$mon,$year)=&horalocal();
	$title =~ s/<\$time_hour\$>/$hour/g;
	$title =~ s/<\$time_min\$>/$min/g;
	$title =~ s/<\$time_sec\$>/$sec/g;
	$title =~ s/<\$time_day\$>/$day/g;
	$title =~ s/<\$time_mon\$>/$mon/g;
	$title =~ s/<\$time_year\$>/$year/g;
	return($title);
}

sub parsePrecision {
	my($precision)=@_;
	$precision=~s/ *//;
	if ($precision =~ /^\d+$/) {
		return($precision);
	} else {
		return(2);
	}
}



#########################################
# parseDimensions(): sets the width and the height
# Arguments:
#  $arguments = the string that contain the dimensions
# Returns:
#  pointer to @dimensios

sub parseDimensions {
  my(@dimensions)=(460, 150);
  my($arguments)=@_;
  &debug("parseDimensions(): Entering parseDimensions\n");
  if (($arguments) && ($arguments =~ /[0-9]+x[0-9]+/)) { 
     my(@splited)=split("x",$arguments); 
     $dimensions[0]=$splited[0];
     $dimensions[1]=$splited[1];
  } else {
     print("parseDimensions() Warning: Invalid dimensions \"$arguments\" for target $targets->[$targetindex][0]\n");
  }
  return(\@dimensions);
}

#########################################
# parseColors(): gets the string containing all colors defined by the user
# and sets an array containing them
# Arguments:
#  $colors= the string that contain the colors
# Returns:
#  pointer to @cores, the array with the colors
  
sub parseColors {
  my($colors)=@_;
  &debug("parseColors(): Entering parseColors ($colors)\n");
  my(@cores)=("FFFFFF","F3F3F3","C8C8C8","969696","8C8C8C","821E1E","000000","000000","FF0000","FF0000","000000");
  if ($colors) {
   my(@splited)=split(",",$colors); # split on the ,
   my(@split);
   for (my($i)=0; $i < scalar(@splited); $i++) {
        if ($splited[$i] =~ /[a-z]#[0-9,A-F]{6}/i) { 
		@split=split("#",$splited[$i]);
                &debug("parseColors(): Found an hexadecimal color definition: $splited[$i] ($split[0])($split[1])\n");
		if ($split[0] =~ /back/i) { $cores[0]=$split[1]; }
		if ($split[0] =~ /canvas/i) { $cores[1]=$split[1]; }
		if ($split[0] =~ /shadea/i) { $cores[2]=$split[1]; }
		if ($split[0] =~ /shadeb/i) { $cores[3]=$split[1]; }
		if ($split[0] =~ /grid/i) { $cores[4]=$split[1]; }
		if ($split[0] =~ /mgrid/i) { $cores[5]=$split[1]; }
		if ($split[0] =~ /font/i) { $cores[6]=$split[1]; }
		if ($split[0] =~ /frame/i) { $cores[7]=$split[1]; }
		if ($split[0] =~ /arrow/i) { $cores[8]=$split[1]; }
		if ($split[0] =~ /in/i) { $cores[9]=$split[1]; }
		if ($split[0] =~ /out/i) { $cores[10]=$split[1]; }
	} elsif ($splited[$i] =~ /[a-z]\$.+/i) { # WHAT A LAMME SOLUTION!!!!! FIX IT NEXT VERSIONS, LAZY BOY!!!!
		@split=split('\$',$splited[$i]);
		&debug("parseColors(): Found a RGB color definition: $splited[$i] ($split[0])($split[1])\n");
		my($temp_color)=$rgb_converter->hex("$split[1]");
                if ($split[0] =~ /back/i) { $cores[0]=($temp_color || "FFFFFF"); }
                if ($split[0] =~ /canvas/i) { $cores[1]=($temp_color || "F3F3F3"); }
                if ($split[0] =~ /shadea/i) { $cores[2]=($temp_color || "C8C8C8"); }
                if ($split[0] =~ /shadeb/i) { $cores[3]=($temp_color || "969696"); }
                if ($split[0] =~ /grid/i) { $cores[4]=($temp_color || "8C8C8C"); }
                if ($split[0] =~ /mgrid/i) { $cores[5]=($temp_color || "821E1E"); }
                if ($split[0] =~ /font/i) { $cores[6]=($temp_color || "000000"); }
                if ($split[0] =~ /frame/i) { $cores[7]=($temp_color || "000000"); }
                if ($split[0] =~ /arrow/i) { $cores[8]=($temp_color || "FF0000"); }
                if ($split[0] =~ /in/i) { $cores[9]=($temp_color || "FF0000"); }
                if ($split[0] =~ /out/i) { $cores[10]=($temp_color || "000000"); }
	} else 	{
		print("parseColors() Warning: Invalid color definition \"$split[1]\" for target $targets->[$targetindex][0]\n");
	}
    }
   } else {
    &debug("parseColors(): no color option defined\n");
   }   
   return(\@cores);
}

###########################################
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


sub organizaGraficos {
  &debug("organizaGraficos(): Entering organizaGraficos\n");
  if ($targets->[$targetindex][17] == 5) { # we got an OID target
		&criaGraficoOid;
  } elsif ($targets->[$targetindex][17] == 6) { # we got a command target
	  	&criaGraficoCommand;
  } else {
	if ($opt_B) { $targets->[$targetindex][6][5]=1 };
	if ($opt_b) { $targets->[$targetindex][6][5]=0 };
	if ($targets->[$targetindex][6][5] == 1) { # deciding if is bytes or bits
		      &criaGraficoBytes;
	} else {
	    	      &criaGraficoBits;
	}
  }
}

sub criaGraficoBytes {
  my(@period)=split(",",$targets->[$targetindex][16]);
  my($bwidth_in,$bwidth_out)=($targets->[$targetindex][1]->[0],$targets->[$targetindex][1]->[0]);
  if (defined($targets->[$targetindex][1]->[1])) { $bwidth_out=$targets->[$targetindex][1]->[1]; }
  my($RRDfile)="$global->[2]/$targets->[$targetindex][0].rrd";
  my($color_back,$color_canvas,$color_shadea,$color_shadeb,$color_grid,$color_mgrid,$color_font,$color_frame,$color_arrow,$color_in,$color_out, $dim_width, $dim_height);
  $bwidth_in=$bwidth_in/8;
  $bwidth_out=$bwidth_out/8;
  # setting default options
  my($opt_inout_def)="DEF:totalin=$RRDfile:octetsin:AVERAGE DEF:totalout=$RRDfile:octetsout:AVERAGE DEF:errin=$RRDfile:errorsin:AVERAGE DEF:errout=$RRDfile:errorsout:AVERAGE";
  my($opt_error)="GPRINT:errin:LAST:\'Errors In - Current\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errin:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errin:MAX:\'Max\\: %.$targets->[$targetindex][20]lf B\/s\\l\' GPRINT:errout:LAST:\'Errors Out - Current\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errout:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errout:MAX:\'Max\\: %.$targets->[$targetindex][20]lf B\/s\\l\'";
  my($opt_rigid)="";
  my($opt_legend)="";
  my($opt_nominor)="";
  my($opt_altautoscale)="";
  # reconfiguring dimension
  if ($$targets[$targetindex][7]->[0] ne "") { $dim_width=$$targets[$targetindex][7]->[0]; }
  if ($$targets[$targetindex][7]->[1] ne "") { $dim_height=$$targets[$targetindex][7]->[1]; }
  # reconfiguring colors
  if ($$targets[$targetindex][8]->[0] ne "") { $color_back="#"."$$targets[$targetindex][8]->[0]"; }
  if ($$targets[$targetindex][8]->[1] ne "") { $color_canvas="#"."$$targets[$targetindex][8]->[1]"; }
  if ($$targets[$targetindex][8]->[2] ne "") { $color_shadea="#"."$$targets[$targetindex][8]->[2]"; }
  if ($$targets[$targetindex][8]->[3] ne "") { $color_shadeb="#"."$$targets[$targetindex][8]->[3]"; }
  if ($$targets[$targetindex][8]->[4] ne "") { $color_grid="#"."$$targets[$targetindex][8]->[4]"; }
  if ($$targets[$targetindex][8]->[5] ne "") { $color_mgrid="#"."$$targets[$targetindex][8]->[5]"; }
  if ($$targets[$targetindex][8]->[6] ne "") { $color_font="#"."$$targets[$targetindex][8]->[6]"; }
  if ($$targets[$targetindex][8]->[7] ne "") { $color_frame="#"."$$targets[$targetindex][8]->[7]"; }
  if ($$targets[$targetindex][8]->[8] ne "") { $color_arrow="#"."$$targets[$targetindex][8]->[8]"; }
  if ($$targets[$targetindex][8]->[9] ne "") { $color_in="#"."$$targets[$targetindex][8]->[9]"; }
  if ($$targets[$targetindex][8]->[10] ne "") { $color_out="#"."$$targets[$targetindex][8]->[10]"; }
  # reconfiguring graphics options
  if ($$targets[$targetindex][6]->[0] == -1) { $opt_error=""; }
  if ($$targets[$targetindex][6]->[1] == 1) { $opt_inout_def="DEF:totalout=$RRDfile:octetsin:AVERAGE DEF:totalin=$RRDfile:octetsout:AVERAGE DEF:errout=$RRDfile:errorsin:AVERAGE DEF:errin=$RRDfile:errorsout:AVERAGE"; }
  if ($$targets[$targetindex][6]->[2] == 1) { 
  	my($max_temp);
  	if ($bwidth_in > $bwidth_out) { $max_temp=$bwidth_in; } else { $max_temp=$bwidth_out; }
  	$opt_rigid="--rigid -u $max_temp"; 
  }
  if ($$targets[$targetindex][6]->[3] == -1) { $opt_legend="--no-legend"; }
  if ($$targets[$targetindex][6]->[7] == -1) { $opt_nominor="--no-minor"; }
  if ($$targets[$targetindex][6]->[8] == 1) { $opt_altautoscale="--alt-autoscale"; }
  # reconfiguring text options
  if ($$targets[$targetindex][9] eq "") { $$targets[$targetindex][9]="Bytes In\/Out"; }
  if ($$targets[$targetindex][10] eq "") { $$targets[$targetindex][10]="Bytes In\/Out for Interface $targets->[$targetindex][5] of $targets->[$targetindex][2]"; }
  if ($$targets[$targetindex][11]->[0] eq "") { $$targets[$targetindex][11]->[0]="Bytes In"; }
  if ($$targets[$targetindex][11]->[1] eq "") { $$targets[$targetindex][11]->[1]="Bytes Out"; }
  if ($$targets[$targetindex][13] eq "") { $$targets[$targetindex][13]="kB/s"; }
  my($opt_imgformat)=lc($$global[5]);
  # end of reconfigure
  &debug("criaGraficoBytes(): Colors are $color_back, $color_canvas, $color_shadea, $color_shadeb, $color_grid, $color_mgrid, $color_font, $color_frame, $color_arrow, $color_in, $color_out\ncriaGraficoBytes(): Options are $$targets[$targetindex][6]->[0] $$targets[$targetindex][6]->[1] $$targets[$targetindex][6]->[2] $$targets[$targetindex][6]->[3] $$targets[$targetindex][6]->[4] $$targets[$targetindex][6]->[5]\ncriaGraficoBytes(): Dimensions are $$targets[$targetindex][7]->[0] x $$targets[$targetindex][7]->[1]\n");
  my($start);
  while ($start=shift(@period)) {
	  print(RRDTOOL "graph $global->[3]/$targets->[$targetindex][0]$start.$opt_imgformat -a $$global[5] -b 1000 $opt_altautoscale $opt_rigid -s $start -e -$targets->[$targetindex][19] $opt_legend $opt_nominor -w $dim_width -h $dim_height -c BACK$color_back -c CANVAS$color_canvas -c SHADEA$color_shadea -c SHADEB$color_shadeb -c GRID$color_grid -c MGRID$color_mgrid -c FONT$color_font -c FRAME$color_frame -c ARROW$color_arrow -v \" $$targets[$targetindex][9] \" -t \"$$targets[$targetindex][10]\" $opt_inout_def CDEF:deltain=totalin,errin,-,0,LT,0,totalin,errin,-,IF CDEF:in=deltain,0,LT,0,deltain,IF,$bwidth_in,GT,$bwidth_in,deltain,IF CDEF:deltaout=totalout,errout,-,0,LT,0,totalout,errout,-,IF CDEF:out=deltaout,0,LT,0,deltaout,IF,$bwidth_out,GT,$bwidth_out,deltaout,IF CDEF:kbin=in,1000,\/ CDEF:kbout=out,1000,\/ CDEF:percbin=in,100,*,$bwidth_in,\/ CDEF:percbout=out,100,*,$bwidth_out,\/ AREA:in$color_in:\"$$targets[$targetindex][11]->[0]\" LINE2:out$color_out:\"$$targets[$targetindex][11]->[1]\\l\" GPRINT:kbin:LAST:\'$$targets[$targetindex][11]->[0] - Now\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:LAST:\' (%.1lf%%)\' GPRINT:kbin:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:AVERAGE:\' (%.1lf%%)\' GPRINT:kbin:MAX:\'Max\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:MAX:\' (%.1lf%%)\\l\' GPRINT:kbout:LAST:\'$$targets[$targetindex][11]->[1] - Now\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:LAST:\' (%.1lf%%)\' GPRINT:kbout:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:AVERAGE:\' (%.1lf%%)\' GPRINT:kbout:MAX:\'Max\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:MAX:\' (%.1lf%%)\\l\' COMMENT:\'Max bytes for target $targets->[$targetindex][0]\: $bwidth_in - $bwidth_out bytes/sec\\l\' $opt_error\n")|| die("criaGraficoBytes() Fatal: Could not print to filehandle RRDTOOL: $!\n");
  }
}

sub criaGraficoBits {
  my(@period)=split(",",$targets->[$targetindex][16]);
  my($bwidth_in,$bwidth_out)=($targets->[$targetindex][1]->[0],$targets->[$targetindex][1]->[0]);
  if (defined($targets->[$targetindex][1]->[1])) { $bwidth_out=$targets->[$targetindex][1]->[1]; }
  my($bytes_bwidth_in)=$bwidth_in/8;
  my($bytes_bwidth_out)=$bwidth_out/8;
  my($RRDfile)="$global->[2]/$targets->[$targetindex][0].rrd";
  my($color_back,$color_canvas,$color_shadea,$color_shadeb,$color_grid,$color_mgrid,$color_font,$color_frame,$color_arrow,$color_in,$color_out, $dim_width, $dim_height);
  # setting default options
  my($opt_inout_def)="DEF:totalin=$RRDfile:octetsin:AVERAGE DEF:totalout=$RRDfile:octetsout:AVERAGE DEF:errin=$RRDfile:errorsin:AVERAGE DEF:errout=$RRDfile:errorsout:AVERAGE";
  my($opt_error)="GPRINT:errin:LAST:\'Errors In - Current\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errin:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errin:MAX:\'Max\\: %.$targets->[$targetindex][20]lf B\/s\\l\' GPRINT:errout:LAST:\'Errors Out - Current\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errout:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf B\/s\' GPRINT:errout:MAX:\'Max\\: %.$targets->[$targetindex][20]lf B\/s\\l\'";
  my($opt_rigid)="";
  my($opt_legend)="";
  my($opt_nominor)="";
  my($opt_altautoscale)="";
  # reconfiguring dimension
  $dim_width=$$targets[$targetindex][7]->[0];
  $dim_height=$$targets[$targetindex][7]->[1];
  # reconfiguring colors
  if ($$targets[$targetindex][8]->[0] ne "") { $color_back="#"."$$targets[$targetindex][8]->[0]"; }
  if ($$targets[$targetindex][8]->[1] ne "") { $color_canvas="#"."$$targets[$targetindex][8]->[1]"; }
  if ($$targets[$targetindex][8]->[2] ne "") { $color_shadea="#"."$$targets[$targetindex][8]->[2]"; }
  if ($$targets[$targetindex][8]->[3] ne "") { $color_shadeb="#"."$$targets[$targetindex][8]->[3]"; }
  if ($$targets[$targetindex][8]->[4] ne "") { $color_grid="#"."$$targets[$targetindex][8]->[4]"; }
  if ($$targets[$targetindex][8]->[5] ne "") { $color_mgrid="#"."$$targets[$targetindex][8]->[5]"; }
  if ($$targets[$targetindex][8]->[6] ne "") { $color_font="#"."$$targets[$targetindex][8]->[6]"; }
  if ($$targets[$targetindex][8]->[7] ne "") { $color_frame="#"."$$targets[$targetindex][8]->[7]"; }
  if ($$targets[$targetindex][8]->[8] ne "") { $color_arrow="#"."$$targets[$targetindex][8]->[8]"; }
  if ($$targets[$targetindex][8]->[9] ne "") { $color_in="#"."$$targets[$targetindex][8]->[9]"; }
  if ($$targets[$targetindex][8]->[10] ne "") { $color_out="#"."$$targets[$targetindex][8]->[10]"; }
  # reconfiguring graphics options
  if ($$targets[$targetindex][6]->[0] == -1) { $opt_error=""; }
  if ($$targets[$targetindex][6]->[1] == 1) { $opt_inout_def="DEF:totalout=$RRDfile:octetsin:AVERAGE DEF:totalin=$RRDfile:octetsout:AVERAGE DEF:errout=$RRDfile:errorsin:AVERAGE DEF:errin=$RRDfile:errorsout:AVERAGE"; }
  if ($$targets[$targetindex][6]->[2] == 1) { 
  	my($max_temp);
  	if ($bwidth_in > $bwidth_out) { $max_temp=$bwidth_in } else { $max_temp=$bwidth_out }
  	$opt_rigid="--rigid -u $max_temp"; 
  }
  if ($$targets[$targetindex][6]->[3] == -1) { $opt_legend="--no-legend"; }
  if ($$targets[$targetindex][6]->[7] == -1) { $opt_nominor="--no-minor"; }
  if ($$targets[$targetindex][6]->[8] == 1) { $opt_altautoscale="--alt-autoscale"; }
  # reconfiguring text options
  if ($$targets[$targetindex][9] eq "") { $$targets[$targetindex][9]="Bits In\/Out"; }
  if ($$targets[$targetindex][10] eq "") { $$targets[$targetindex][10]="Bits In\/Out for Interface $targets->[$targetindex][5] of $targets->[$targetindex][2]"; }
  if ($$targets[$targetindex][11]->[0] eq "") { $$targets[$targetindex][11]->[0]="Bits In"; }
  if ($$targets[$targetindex][11]->[1] eq "") { $$targets[$targetindex][11]->[1]="Bits Out"; }
  if ($$targets[$targetindex][13] eq "") { $$targets[$targetindex][13]="kb/s"; }
  my($opt_imgformat)=lc($$global[5]);
  # end of reconfigure
  &debug("criaGraficoBits(): Colors are $color_back, $color_canvas, $color_shadea, $color_shadeb, $color_grid, $color_mgrid, $color_font, $color_frame, $color_arrow, $color_in, $color_out\ncriaGraficoBits(): Options are $$targets[$targetindex][6]->[0] $$targets[$targetindex][6]->[1] $$targets[$targetindex][6]->[2] $$targets[$targetindex][6]->[3] $$targets[$targetindex][6]->[4] $$targets[$targetindex][6]->[5]\ncriaGraficoBits(): Dimensions are $$targets[$targetindex][7]->[0] x $$targets[$targetindex][7]->[1]\n");
  my($start);
  while ($start=shift(@period)) {
	  print(RRDTOOL "graph $global->[3]/$targets->[$targetindex][0]$start.$opt_imgformat -a $$global[5] -b 1000 $opt_altautoscale $opt_rigid -s $start -e -$targets->[$targetindex][19] $opt_legend $opt_nominor -w $dim_width -h $dim_height -c BACK$color_back -c CANVAS$color_canvas -c SHADEA$color_shadea -c SHADEB$color_shadeb -c GRID$color_grid -c MGRID$color_mgrid -c FONT$color_font -c FRAME$color_frame -c ARROW$color_arrow -v \"$$targets[$targetindex][9]\" -t \"$$targets[$targetindex][10]\" $opt_inout_def  CDEF:deltain=totalin,errin,-,0,LT,0,totalin,errin,-,IF CDEF:in=deltain,0,LT,0,deltain,IF,$bytes_bwidth_in,GT,$bytes_bwidth_in,deltain,IF CDEF:deltaout=totalout,errout,-,0,LT,0,totalout,errout,-,IF CDEF:out=deltaout,0,LT,0,deltaout,IF,$bytes_bwidth_out,GT,$bytes_bwidth_out,deltaout,IF CDEF:bitsin=in,8,* CDEF:bitsout=out,8,* CDEF:kbitsin=bitsin,1000,\/ CDEF:kbitsout=bitsout,1000,\/ CDEF:percbin=bitsin,100,*,$bwidth_in,\/ CDEF:percbout=bitsout,100,*,$bwidth_out,\/ CDEF:berrin=errin,8,\/ CDEF:berrout=errout,8,\/ AREA:bitsin$color_in:\"$$targets[$targetindex][11]->[0]\" LINE2:bitsout$color_out:\"$$targets[$targetindex][11]->[1]\\l\" GPRINT:kbitsin:LAST:\'$$targets[$targetindex][11]->[0] - Now\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:LAST:\' (%.1lf%%)\' GPRINT:kbitsin:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:AVERAGE:\' (%.1lf%%)\' GPRINT:kbitsin:MAX:\'Max\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbin:MAX:\' (%.1lf%%)\\l\' GPRINT:kbitsout:LAST:\'$$targets[$targetindex][11]->[1] - Now\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:LAST:\' (%.1lf%%)\' GPRINT:kbitsout:AVERAGE:\'Avg\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:AVERAGE:\' (%.1lf%%)\' GPRINT:kbitsout:MAX:\'Max\\: %.$targets->[$targetindex][20]lf $$targets[$targetindex][13]\\g\' GPRINT:percbout:MAX:\' (%.1lf%%)\\l\' COMMENT:\'Max bits for target $targets->[$targetindex][0]\\: $bwidth_in - $bwidth_out bits/sec \\l\' $opt_error\n") || die("criaGraficoBits() Fatal: Could not print to filehandle RRDTOOL: $!\n");
  }
}

sub criaGraficoOid {
  my(@period)=split(",",$targets->[$targetindex][16]);
  my($max)=($targets->[$targetindex][1]->[0]);
  my($max_desc)=($targets->[$targetindex][1]->[2]); 
  my($color_back,$color_canvas,$color_shadea,$color_shadeb,$color_grid,$color_mgrid,$color_font,$color_frame,$color_arrow,$color_in,$color_out, $dim_width, $dim_height);
  # setting default options
  my($opt_rigid)="";
  my($opt_legend)="";
  my($opt_nominor)="";
  my($opt_altautoscale)="";
  # reconfiguring dimension
  if ($$targets[$targetindex][7]->[0] ne "") { $dim_width=$$targets[$targetindex][7]->[0]; }
  if ($$targets[$targetindex][7]->[1] ne "") { $dim_height=$$targets[$targetindex][7]->[1]; }
  # reconfiguring colors
  if ($$targets[$targetindex][8]->[0] ne "") { $color_back="#"."$$targets[$targetindex][8]->[0]"; }
  if ($$targets[$targetindex][8]->[1] ne "") { $color_canvas="#"."$$targets[$targetindex][8]->[1]"; }
  if ($$targets[$targetindex][8]->[2] ne "") { $color_shadea="#"."$$targets[$targetindex][8]->[2]"; }
  if ($$targets[$targetindex][8]->[3] ne "") { $color_shadeb="#"."$$targets[$targetindex][8]->[3]"; }
  if ($$targets[$targetindex][8]->[4] ne "") { $color_grid="#"."$$targets[$targetindex][8]->[4]"; }
  if ($$targets[$targetindex][8]->[5] ne "") { $color_mgrid="#"."$$targets[$targetindex][8]->[5]"; }
  if ($$targets[$targetindex][8]->[6] ne "") { $color_font="#"."$$targets[$targetindex][8]->[6]"; }
  if ($$targets[$targetindex][8]->[7] ne "") { $color_frame="#"."$$targets[$targetindex][8]->[7]"; }
  if ($$targets[$targetindex][8]->[8] ne "") { $color_arrow="#"."$$targets[$targetindex][8]->[8]"; }
  if ($$targets[$targetindex][8]->[9] ne "") { $color_in="#"."$$targets[$targetindex][8]->[9]"; }
  if ($$targets[$targetindex][8]->[10] ne "") { $color_out="#"."$$targets[$targetindex][8]->[10]"; }
  # ************************ There is no noerror option
  # ************************ There is no invert option
  if ($$targets[$targetindex][6]->[2] == 1) { $opt_rigid="--rigid -u $max"; }
  if ($$targets[$targetindex][6]->[3] == -1) { $opt_legend="--no-legend"; }
  if ($$targets[$targetindex][6]->[7] == -1) { $opt_nominor="--no-minor"; }
  if ($$targets[$targetindex][6]->[8] == 1) { $opt_altautoscale="--alt-autoscale"; }
  # reconfiguring text options
  if ($$targets[$targetindex][9] eq "") { $$targets[$targetindex][9]="Data collected via SNMP"; }
  if ($$targets[$targetindex][10] eq "") { $$targets[$targetindex][10]="Data for host $targets->[$targetindex][2]"; }
  if ($$targets[$targetindex][13] eq "") { $$targets[$targetindex][13]="kB/s"; }
  my($opt_imgformat)=lc($$global[5]);
  # end of reconfigure
  &debug("criaGraficoOid(): Colors are $color_back, $color_canvas, $color_shadea, $color_shadeb, $color_grid, $color_mgrid, $color_font, $color_frame, $color_arrow, $color_in, $color_out\ncriaGraficoOid(): Options are $$targets[$targetindex][6]->[0] $$targets[$targetindex][6]->[1] $$targets[$targetindex][6]->[2] $$targets[$targetindex][6]->[3] $$targets[$targetindex][6]->[4] $$targets[$targetindex][6]->[5]\ncriaGraficoOid(): Dimensions are $$targets[$targetindex][7]->[0] x $$targets[$targetindex][7]->[1]\ncriaGraficoOid(): Oid definitions are $targets->[$targetindex][18]\n");
  my($start);
  while ($start=shift(@period)) {
	  print(RRDTOOL "graph $global->[3]/$targets->[$targetindex][0]$start.$opt_imgformat -a $$global[5] -b $targets->[$targetindex][12] $opt_altautoscale $opt_rigid -s $start -e -$targets->[$targetindex][19] $opt_legend $opt_nominor -w $dim_width -h $dim_height -c BACK$color_back -c CANVAS$color_canvas -c SHADEA$color_shadea -c SHADEB$color_shadeb -c GRID$color_grid -c MGRID$color_mgrid -c FONT$color_font -c FRAME$color_frame -c ARROW$color_arrow -v \"$$targets[$targetindex][9]\" -t \"$$targets[$targetindex][10]\" $$targets[$targetindex][18] \n") || die("criaGraficoOid() Fatal: Could not print to filehandle RRDTOOL: $!\n");
  }
}


sub criaGraficoCommand {
	my(@period)=split(",",$targets->[$targetindex][16]);
	my($max)=($targets->[$targetindex][1]->[0]);
	my($max_desc)=($targets->[$targetindex][1]->[2]);
	my($color_back,$color_canvas,$color_shadea,$color_shadeb,$color_grid,$color_mgrid,$color_font,$color_frame,$color_arrow,$dim_width,$dim_height);
	# setting default options
	my($opt_rigid)="";
	my($opt_legend)="";
	my($opt_nominor)="";
        my($opt_altautoscale)="";
	# reconfiguring dimension
	if ($$targets[$targetindex][7]->[0] ne "") { $dim_width=$$targets[$targetindex][7]->[0]; }
	if ($$targets[$targetindex][7]->[1] ne "") { $dim_height=$$targets[$targetindex][7]->[1]; }
	# reconfiguring colors
	if ($$targets[$targetindex][8]->[0] ne "") { $color_back="#"."$$targets[$targetindex][8]->[0]"; }
	if ($$targets[$targetindex][8]->[1] ne "") { $color_canvas="#"."$$targets[$targetindex][8]->[1]"; }
	if ($$targets[$targetindex][8]->[2] ne "") { $color_shadea="#"."$$targets[$targetindex][8]->[2]"; }
	if ($$targets[$targetindex][8]->[3] ne "") { $color_shadeb="#"."$$targets[$targetindex][8]->[3]"; }
	if ($$targets[$targetindex][8]->[4] ne "") { $color_grid="#"."$$targets[$targetindex][8]->[4]"; }
	if ($$targets[$targetindex][8]->[5] ne "") { $color_mgrid="#"."$$targets[$targetindex][8]->[5]"; }
	if ($$targets[$targetindex][8]->[6] ne "") { $color_font="#"."$$targets[$targetindex][8]->[6]"; }
	if ($$targets[$targetindex][8]->[7] ne "") { $color_frame="#"."$$targets[$targetindex][8]->[7]"; }
	if ($$targets[$targetindex][8]->[8] ne "") { $color_arrow="#"."$$targets[$targetindex][8]->[8]"; }
	# ************************ There is no noerror option
	# ************************ There is no invert option
	if ($$targets[$targetindex][6]->[2] == 1) { $opt_rigid="--rigid -u $max"; }
	if ($$targets[$targetindex][6]->[3] == -1) { $opt_legend="--no-legend"; }
	if ($$targets[$targetindex][6]->[7] == -1) { $opt_nominor="--no-minor"; }
        if ($$targets[$targetindex][6]->[8] == 1) { $opt_altautoscale="--alt-autoscale"; }
	# reconfiguring text options
	if ($$targets[$targetindex][9] eq "") { $$targets[$targetindex][9]="Command Outputs"; }
	if ($$targets[$targetindex][10] eq "") { $$targets[$targetindex][10]="Output from $targets->[$targetindex][2]"; }
	if ($$targets[$targetindex][13] eq "") { $$targets[$targetindex][13]="kB/s"; }
	my($opt_imgformat)=lc($$global[5]);
	# end of reconfigure
	&debug("criaGraficoCommand(): Colors are $color_back, $color_canvas, $color_shadea, $color_shadeb, $color_grid, $color_mgrid, $color_font, $color_frame, $color_arrow\ncriaGraficoCommand(): Options are $$targets[$targetindex][6]->[0] $$targets[$targetindex][6]->[1] $$targets[$targetindex][6]->[2] $$targets[$targetindex][6]->[3] $$targets[$targetindex][6]->[4] $$targets[$targetindex][6]->[5]\ncriaGraficoCommand(): Dimensions are $$targets[$targetindex][7]->[0] x $$targets[$targetindex][7]->[1]\ncriaGraficoCommand(): Command definitions are $targets->[$targetindex][18]\n");
	my($start);
	while ($start=shift(@period)) {
		print(RRDTOOL "graph $global->[3]/$targets->[$targetindex][0]$start.$opt_imgformat -a $$global[5] -b $targets->[$targetindex][12] $opt_altautoscale $opt_rigid -s $start -e -$targets->[$targetindex][19] $opt_legend $opt_nominor -w $dim_width -h $dim_height -c BACK$color_back -c CANVAS$color_canvas -c SHADEA$color_shadea -c SHADEB$color_shadeb -c GRID$color_grid -c MGRID$color_mgrid -c FONT$color_font -c FRAME$color_frame -c ARROW$color_arrow -v \"$$targets[$targetindex][9]\" -t \"$$targets[$targetindex][10]\" $$targets[$targetindex][18] \n") || die("criaGraficoCommand() Fatal: Could not print to filehandle RRDTOOL: $!\n");
	}
}



sub readconf  {
 my($configfile)=@_;
 my(@splited, @global, @targets, $target_name);
 # Setting targets defaults
 my(@default)=("name","1G","localhost","public",161,0,"","460x150","back#FFFFFF","","","","1000","",1,10,"-1day,-1week,-1month,-1year",0,"",600,2);
 # Setting global defaults
 @global[1,2,3,4,5]=("/usr/local/bin/rrdtool","/usr/local/rrdfiles/","/usr/local/htdocs/","$FindBin::Bin/templates/en/","PNG");
 my($accept_new_target)=1;
 my($index)=-1; # target targetindex
 open(CONF,"$configfile") || die("readconf() Fatal: Could not read configuration file $configfile ($!)\n"); 
 while (<CONF>) {
  chomp($_); # remove nl
  if (($_ =~ /^\[(.+)\] */) && ($_ !~ /^#.*/))  { # if is a [xxxx] and there isnt a ^#
   $target_name=$1;		      # target gets what is inside []
   if ($target_name ne "global") { # if the target is not global
    if ($accept_new_target) { $index++; } else { $accept_new_target=1 } # increment the index number only if the target has 
    									# a graph=true|yes or set the default for the next target
    $targets[$index]=[ @default ];	# here the target gets the defaults
    $targets[$index][0]=$target_name;	# now the target name
   }
  }
  if (($_ =~ / *= */) && ($_ !~ /^#.*/)) {
   @splited=split(" *= *",$_);
   if ($target_name eq "global") {
     if ($splited[0] =~ /rrdtool\Z/i) { $global[1]=$splited[1]; }
     elsif ($splited[0] =~ /rrddir\Z/i) { $global[2]=$splited[1]; }
     elsif ($splited[0] =~ /graphdir\Z/i) { $global[3]=$splited[1]; }
     elsif ($splited[0] =~ /template\Z/i) { $global[4]=$splited[1]; }
     elsif ($splited[0] =~ /imgformat\Z/i) { $global[5]=$splited[1]; } # optional
     # re-setting the defaults
     elsif ($splited[0] =~ /max\Z/i) { $default[1]=$splited[1]; } # mandatory
     elsif ($splited[0] =~ /host\Z/i) { $default[2]=$splited[1]; } # optional
     elsif ($splited[0] =~ /community\Z/i) { $default[3]=$splited[1]; } #optional
     elsif ($splited[0] =~ /port\Z/i) { $default[4]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface\Z/i)  { print("Warning: We *can not* set a default interface\n"); } # optional
     elsif ($splited[0] =~ /interface_name\Z/i) { print("Warning: we *can not* use a default interface_name\n"); }
     elsif ($splited[0] =~ /interface_mac\Z/i) { print("Warning: we *can not* use a default interface_mac\n"); }
     elsif ($splited[0] =~ /interface_ip\Z/i) { print("Warning: we *can not* use a default interface_desc\n"); }
     elsif ($splited[0] =~ /oids\Z/i) { print("Warning: we *can not* use a default oid\n"); }
     elsif ($splited[0] =~ /command\Z/i) { print("Warning: we *can not* use a default command\n"); }
     elsif ($splited[0] =~ /oiddefs\Z/i) { print("Warning: we *can not* use a default oiddefs\n"); }
     elsif ($splited[0] =~ /commdefs\Z/i) { print("Warning: we *can not* use a default commanddefs\n"); }
     elsif ($splited[0] =~ /options\Z/i) { $default[6]=$splited[1]; } # optional
     elsif ($splited[0] =~ /dimension\Z/i) { $default[7]=$splited[1]; } # optional
     elsif ($splited[0] =~ /colors\Z/i) { $default[8]=$splited[1]; } # optional
     elsif ($splited[0] =~ /ylegend\Z/i) { $default[9]=$splited[1]; } # optional
     elsif ($splited[0] =~ /title\Z/i) { $default[10]=$splited[1]; } # optional
     elsif ($splited[0] =~ /legends\Z/i) { $default[11]=$splited[1]; } # optional
     elsif ($splited[0] =~ /kilo\Z/i) { $default[12]=$splited[1]; } # optional
     elsif ($splited[0] =~ /shortlegend\Z/i) { $default[13]=$splited[1]; } # optional
     elsif ($splited[0] =~ /retry\Z/i) { $default[14]=$splited[1]; } # optional
     elsif ($splited[0] =~ /timeout\Z/i) { $default[15]=$splited[1]; } # optional
     elsif ($splited[0] =~ /periods\Z/i) { $default[16]=$splited[1]; } # optional
     elsif ($splited[0] =~ /hbeat\Z/i) { $default[19]=$splited[1]; } #optional
     elsif ($splited[0] =~ /precision\Z/i) { $default[20]=$splited[1]; } # optional
   } else { # if it is a normal target
     $targets[$index][0]=$target_name; 
     if ($splited[0] =~ /max\Z/i) { $targets[$index][1]=$splited[1]; } # mandatory
     elsif ($splited[0] =~ /host\Z/i) { $targets[$index][2]=$splited[1]; } # optional
     elsif ($splited[0] =~ /community\Z/i) { $targets[$index][3]=$splited[1]; } #optional
     elsif ($splited[0] =~ /port\Z/i) { $targets[$index][4]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface\Z/i)  { $targets[$index][17]=1; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_name\Z/i)  { $targets[$index][17]=2; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_mac\Z/i)  { $targets[$index][17]=3; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /interface_ip\Z/i)  { $targets[$index][17]=4; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /oids\Z/i) { $targets[$index][17]=5; $targets[$index][5]=$splited[1]; } # optional 
     elsif ($splited[0] =~ /command/i) { $targets[$index][17]=6; $targets[$index][5]=$splited[1]; } # optional
     elsif ($splited[0] =~ /options\Z/i) { $targets[$index][6]=$default[6].",".$splited[1]; } # optional (default . new)
     elsif ($splited[0] =~ /dimension\Z/i) { $targets[$index][7]=$splited[1]; } # optional
     elsif ($splited[0] =~ /colors\Z/i) { $targets[$index][8]=$default[8].",".$splited[1]; } # optional (default . new)
     elsif ($splited[0] =~ /ylegend\Z/i) { $targets[$index][9]=$splited[1]; } # optional
     elsif ($splited[0] =~ /title\Z/i) { $targets[$index][10]=$splited[1]; } # optional
     elsif ($splited[0] =~ /legends\Z/i) { $targets[$index][11]=$splited[1]; } # optional
     elsif ($splited[0] =~ /kilo\Z/i) { $targets[$index][12]=$splited[1]; } # optional
     elsif ($splited[0] =~ /shortlegend\Z/i) { $targets[$index][13]=$splited[1]; } # optional
     elsif ($splited[0] =~ /retry\Z/i) { $targets[$index][14]=$splited[1]; } # optional
     elsif ($splited[0] =~ /timeout\Z/i) { $targets[$index][15]=$splited[1]; } # optional
     elsif ($splited[0] =~ /periods\Z/i) { $targets[$index][16]=$splited[1]; } # optional
     elsif ($splited[0] =~ /oiddefs\Z/i) { $targets[$index][18]=$splited[1]; } # mandatory for oid targets
     elsif ($splited[0] =~ /commdefs\Z/i) { $targets[$index][18]=$splited[1]; } # mandatory for command targets
     elsif ($splited[0] =~ /hbeat\Z/i) { $targets[$index][19]=$splited[1]; } # optional
     elsif ($splited[0] =~ /graph\Z/i) { if ($splited[1] =~ /false|no/i) { $accept_new_target=0; } else { $accept_new_target=1; } }
     elsif ($splited[0] =~ /precision\Z/i) { $default[20]=$splited[1]; }
   }
  }
 }
 if ($accept_new_target==0) { $index-- } # if the last target should not be graphed
 #&showTargets(\@targets,\@global);
 close(CONF);
 $global[0]=$index;
 return(\@targets,\@global); # return the pointers
}

#sub showTargets {
#  my($targets,$global)=@_;
#  for (my($i)=0; $i <= $global->[0]; $i++) {
#   print("Showing target #($i)\n");
#   for (my($j)=0; $j <= 15; $j++) {
#     print("[$targets->[$i][0]][$j]: $targets->[$i][$j]\n");
#   }
#  }
#exit(0);
#}

sub debug {
 if ($opt_d) {
  my($parm1) = @_;
  print($parm1);
 }
}

sub createTemplateIndex {
  &debug("Creating $global->[3]/index-$randomic.temp\n");
  &debug("Permited variables in main-header.html: <\$time_[hour,min,sec,day,mon,year]\$>\n");
  my($sec,$min,$hour,$day,$mon,$year)=&horalocal(); #$mon++; $year+=1900;
  open(INDEX, ">$global->[3]/index-$randomic.temp") || die("createTemplateIndex() Fatal: Could not create index.html in $global->[3] ($!)\n");
  open(TEMPLATE, "$global->[4]/main-header.html") || die ("createTemplateIndex() Fatal: Could not open template file $global->[4]/main-header.html ($!)\n");
  while(<TEMPLATE>) {
	#print $_;
	$_ =~ s/<\$time_hour\$>/$hour/g;
	$_ =~ s/<\$time_min\$>/$min/g;
	$_ =~ s/<\$time_sec\$>/$sec/g;
	$_ =~ s/<\$time_day\$>/$day/g;
	$_ =~ s/<\$time_mon\$>/$mon/g;
	$_ =~ s/<\$time_year\$>/$year/g;
	print(INDEX "$_");
  }
  close(TEMPLATE);
}

sub addTemplateIndex {
 my($response)=@_;
 &debug("Permited variables in main-if.html: <\$target_[name,max,hostname,port,community,interface]\$> <\$snmp[ifdesc,sysdesc,sysuptime,syscontact,syslocation,sysname]\$> <\$first_period\$> <\$last_period\$>\n");
 my($snmp_descricao, $snmp_sysuptime, $snmp_syscontact, $snmp_syslocation, $snmp_sysname, $snmp_sysdesc)=("NA","NA","NA","NA","NA","NA");
 if ($$response != 0) {
  if ($targets->[$targetindex][17]!=5) { 
	$snmp_descricao=$$response->{"1.3.6.1.2.1.2.2.1.2.$targets->[$targetindex][5]"};
  } else {
	$snmp_descricao="OID request";                  
  } 
  $snmp_sysdesc=$$response->{'1.3.6.1.2.1.1.1.0'};
  $snmp_sysuptime=$$response->{'1.3.6.1.2.1.1.3.0'};
  $snmp_syscontact=$$response->{'1.3.6.1.2.1.1.4.0'};
  $snmp_syslocation=$$response->{'1.3.6.1.2.1.1.6.0'};
  $snmp_sysname=$$response->{'1.3.6.1.2.1.1.5.0'};
 }
 if ($snmp_descricao eq "") { $snmp_descricao="NA" };
 if ($snmp_sysdesc eq "") { $snmp_sysdesc="NA" };
 if ($snmp_sysuptime eq "") { $snmp_sysuptime="NA" };
 if ($snmp_syscontact eq "") { $snmp_syscontact="NA" };
 if ($snmp_syslocation eq "") { $snmp_syslocation="NA" };
 if ($snmp_sysname eq "") { $snmp_sysname="NA" };
 my(@temp_array)=split(",",$targets->[$targetindex][16]);
 my($first_period)=shift(@temp_array);
 my($last_period)=pop(@temp_array);
 my($imgformat)=substr(lc($$global[5]),0,3); # retrieve only the 3 first caracters (cos of "gif --interlace")
 open(TEMPLATE, "$global->[4]/main-data.html") || die ("addTemplateIndex() Fatal: Could not open template file $global->[4]/main-data.html ($!)\n");
 while(<TEMPLATE>) {
	$_ =~ s/<\$first_period\$>/$first_period/g;
	$_ =~ s/<\$last_period\$>/$last_period/g;
 	$_ =~ s/<\$target_name\$>/$targets->[$targetindex][0]/g;
	$_ =~ s/<\$target_max\$>/$targets->[$targetindex][1]/g;
	$_ =~ s/<\$target_hostname\$>/$targets->[$targetindex][2]/g;
	$_ =~ s/<\$target_community\$>/$targets->[$targetindex][3]/g;
	$_ =~ s/<\$target_port\$>/$targets->[$targetindex][4]/g;
	$_ =~ s/<\$target_interface\$>/$targets->[$targetindex][5]/g;
	$_ =~ s/<\$snmp_ifdesc\$>/$snmp_descricao/g;
	$_ =~ s/<\$snmp_sysdesc\$>/$snmp_sysdesc/g;
	$_ =~ s/<\$snmp_sysuptime\$>/$snmp_sysuptime/g;
	$_ =~ s/<\$snmp_syscontact\$>/$snmp_syscontact/g;
	$_ =~ s/<\$snmp_syslocation\$>/$snmp_syslocation/g;
	$_ =~ s/<\$snmp_sysname\$>/$snmp_sysname/g;
	$_ =~ s/<\$imgformat\$>/$imgformat/g;
 	print(INDEX "$_");
 }
 close(TEMPLATE);
}

sub closeTemplateIndex {
 &debug("Closing $global->[3]/index.html\n");
 &debug("Permited variables in main-trailer.html: <\$time_[hour,min,sec,day,mon,year]\$>\n");
 my($sec,$min,$hour,$day,$mon,$year)=&horalocal(); #$mon++; $year+=1900;
 open(TEMPLATE, "$global->[4]/main-trailer.html");
 while(<TEMPLATE>) {
	$_ =~ s/<\$time_hour\$>/$hour/g;
	$_ =~ s/<\$time_min\$>/$min/g;
	$_ =~ s/<\$time_sec\$>/$sec/g;
	$_ =~ s/<\$time_day\$>/$day/g;
	$_ =~ s/<\$time_mon\$>/$mon/g;
	$_ =~ s/<\$time_year\$>/$year/g;
	print(INDEX "$_");
 }
 close(INDEX);
 close(TEMPLATE);
 &debug("closeTemplateIndex(): moving $global->[3]/index-$randomic.temp to $global->[3]/index.html\n");
 move("$global->[3]/index-$randomic.temp","$global->[3]/index.html") || print("closeTemplateIndex() Warning: Error on moving $global->[3]/index-$randomic.temp -> $global->[3]/index.html ($!)\n");
}


sub horalocal {
 my(@hora)=localtime(time());
 my($var);
 $hora[4]++;
 $hora[5]+=1900;
 for ($var=0; $var<7; $var++) {
  if (length($hora[$var]) <= 1) {
   $hora[$var] = "0".$hora[$var];
  }
 }
 return(@hora);
}

sub addTemplateInterface {
 my($response)=@_;
 my($sec,$min,$hour,$day,$mon,$year)=&horalocal(time()); # $mon++; $year+=1900;
 my($snmp_descricao, $snmp_sysuptime, $snmp_syscontact, $snmp_syslocation, $snmp_sysname, $snmp_sysdesc)=("NA","NA","NA","NA","NA","NA");
 if ($$response != 0) {
	&debug("addTemplateInterface(): we got response, using it\n");
 	if ($targets->[$targetindex][17]!=5) { 
		  $snmp_descricao=$$response->{"1.3.6.1.2.1.2.2.1.2.$targets->[$targetindex][5]"};
	 } else {
		  $snmp_descricao="OID request";
	 }
	 $snmp_sysdesc=$$response->{'1.3.6.1.2.1.1.1.0'};
	 $snmp_sysuptime=$$response->{'1.3.6.1.2.1.1.3.0'};
	 $snmp_syscontact=$$response->{'1.3.6.1.2.1.1.4.0'};
	 $snmp_syslocation=$$response->{'1.3.6.1.2.1.1.6.0'};
	 $snmp_sysname=$$response->{'1.3.6.1.2.1.1.5.0'};
  }
  if ($snmp_descricao eq "") { $snmp_descricao="NA" };
  if ($snmp_sysdesc eq "") { $snmp_sysdesc="NA" };
  if ($snmp_sysuptime eq "") { $snmp_sysuptime="NA" };
  if ($snmp_syscontact eq "") { $snmp_syscontact="NA" };
  if ($snmp_syslocation eq "") { $snmp_syslocation="NA" };
  if ($snmp_sysname eq "") { $snmp_sysname="NA" };
  open(IFHTML, ">$global->[3]/$targets->[$targetindex][0]-$randomic.temp") || die ("addTemplateInterface() Fatal: Could not open interface file $global->[3]/$targets->[$targetindex][0]-$randomic.temp ($!)\n"); 
  open(TEMPLATE_H, "$global->[4]/if-header.html") || die ("addTemplateInterface() Fatal: Could not open template file $global->[4]/if-header.html ($!)\n");
  while(<TEMPLATE_H>) {
 	$_ =~ s/<\$target_name\$>/$targets->[$targetindex][0]/g;
	$_ =~ s/<\$target_max\$>/$targets->[$targetindex][1]/g;
	$_ =~ s/<\$target_hostname\$>/$targets->[$targetindex][2]/g;
	$_ =~ s/<\$target_community\$>/$targets->[$targetindex][3]/g;
	$_ =~ s/<\$target_port\$>/$targets->[$targetindex][4]/g;
	$_ =~ s/<\$target_interface\$>/$targets->[$targetindex][5]/g;
	$_ =~ s/<\$snmp_ifdesc\$>/$snmp_descricao/g;
	$_ =~ s/<\$snmp_sysdesc\$>/$snmp_sysdesc/g;
	$_ =~ s/<\$snmp_sysuptime\$>/$snmp_sysuptime/g;
	$_ =~ s/<\$snmp_syscontact\$>/$snmp_syscontact/g;
	$_ =~ s/<\$snmp_syslocation\$>/$snmp_syslocation/g;
	$_ =~ s/<\$snmp_sysname\$>/$snmp_sysname/g;
	$_ =~ s/<\$time_hour\$>/$hour/g;
	$_ =~ s/<\$time_min\$>/$min/g;
	$_ =~ s/<\$time_sec\$>/$sec/g;
	$_ =~ s/<\$time_day\$>/$day/g;
	$_ =~ s/<\$time_mon\$>/$mon/g;
	$_ =~ s/<\$time_year\$>/$year/g;
	print(IFHTML "$_");
  }
  close(TEMPLATE_H);
  open(TEMPLATE_D, "$global->[4]/if-data.html") || die ("addTemplateInterface() Fatal: Could not open template file $global->[4]/if-data.html ($!)\n");
  my($period);
  my($imgformat)=substr(lc($$global[5]),0,3);
  my(@temp_array)=split(",",$targets->[$targetindex][16]);
  while ($period=shift(@temp_array)) { 
     seek(TEMPLATE_D,0,0);
     while (<TEMPLATE_D>) {
  	$_ =~ s/<\$target_name\$>/$targets->[$targetindex][0]/g;
	$_ =~ s/<\$target_max\$>/$targets->[$targetindex][1]/g;
	$_ =~ s/<\$target_hostname\$>/$targets->[$targetindex][2]/g;
	$_ =~ s/<\$target_community\$>/$targets->[$targetindex][3]/g;
	$_ =~ s/<\$target_port\$>/$targets->[$targetindex][4]/g;
	$_ =~ s/<\$target_interface\$>/$targets->[$targetindex][5]/g;
	$_ =~ s/<\$snmp_ifdesc\$>/$snmp_descricao/g;
	$_ =~ s/<\$snmp_sysdesc\$>/$snmp_sysdesc/g;
	$_ =~ s/<\$snmp_sysuptime\$>/$snmp_sysuptime/g;
	$_ =~ s/<\$snmp_syscontact\$>/$snmp_syscontact/g;
	$_ =~ s/<\$snmp_syslocation\$>/$snmp_syslocation/g;
	$_ =~ s/<\$snmp_sysname\$>/$snmp_sysname/g;
	$_ =~ s/<\$period\$>/$period/g;
	$_ =~ s/<\$imgformat\$>/$imgformat/g;
	print(IFHTML "$_");
     }
  }
  close(TEMPLATE_D);
  open(TEMPLATE_T, "$global->[4]/if-trailer.html") || die ("addTemplateInterface() Fatal: Could not open template file $global->[4]/if-trailer.html ($!)\n");
  while(<TEMPLATE_T>) {	
	$_ =~ s/<\$target_name\$>/$targets->[$targetindex][0]/g;
	$_ =~ s/<\$target_max\$>/$targets->[$targetindex][1]/g;
	$_ =~ s/<\$target_hostname\$>/$targets->[$targetindex][2]/g;
	$_ =~ s/<\$target_community\$>/$targets->[$targetindex][3]/g;
	$_ =~ s/<\$target_port\$>/$targets->[$targetindex][4]/g;
	$_ =~ s/<\$target_interface\$>/$targets->[$targetindex][5]/g;
	$_ =~ s/<\$snmp_ifdesc\$>/$snmp_descricao/g;
	$_ =~ s/<\$snmp_sysdesc\$>/$snmp_sysdesc/g;
	$_ =~ s/<\$snmp_sysuptime\$>/$snmp_sysuptime/g;
	$_ =~ s/<\$snmp_syscontact\$>/$snmp_syscontact/g;
	$_ =~ s/<\$snmp_syslocation\$>/$snmp_syslocation/g;
	$_ =~ s/<\$snmp_sysname\$>/$snmp_sysname/g;
	$_ =~ s/<\$time_hour\$>/$hour/g;
	$_ =~ s/<\$time_min\$>/$min/g;
	$_ =~ s/<\$time_sec\$>/$sec/g;
	$_ =~ s/<\$time_day\$>/$day/g;
	$_ =~ s/<\$time_mon\$>/$mon/g;
	$_ =~ s/<\$time_year\$>/$year/g;
	print(IFHTML "$_");
  }
  close(TEMPLATE_T);
  close(IFHTML);
  &debug("addTemplateInterface(): moving $global->[3]/$targets->[$targetindex][0]-$randomic.temp to $global->[3]/$targets->[$targetindex][0].html\n");
  move("$global->[3]/$targets->[$targetindex][0]-$randomic.temp","$global->[3]/$targets->[$targetindex][0].html") || print("addTemplateInterface() Warning: Error on moving $global->[3]/index-$randomic.temp -> $global->[3]/index.html ($!)\n");
}



##########################################
# findInterfaceIndex(): try to find the interface index of the target
# Arguments:
# 	none
# Returns:
# 	1 - if the interface index was found
# 	0 - if the interface index could not be found

sub findInterfaceIndex {
     if ($targets->[$targetindex][17] == 1) { # if the target has the interface number
	     &debug("findInterfaceIndex(): we already have the index, we dont need to find it\n");
	     return(1);
     } elsif ($targets->[$targetindex][17] == 5) { # if the target is an OID target
	     &debug("findInterfaceIndex(): this is an OID target, we dont need to find the index\n");
	     return(1);
     } else { # if the target is a mac, ip or name
             &debug("findInterfaceIndex(): We must have the interface index to go on\n");
             my $OIDIfIndexTable = "1.3.6.1.2.1.2.2.1.1"; # the interface index table
	     # if there is no answer from the SNMP agent, prints a warning and sets the interface type to index
             # so it does not passes trough the &findIndexBy*() functions.
             if (defined($response=$session->get_table($OIDIfIndexTable))) { # we need the interface index to go on
		     &debug("findInterfaceIndex(): the SNMP session is defined, lets go on with this\n"); 
		     if ($targets->[$targetindex][17] == 2) {
				($targets->[$targetindex][5]=&findIndexByName) || return(0);
		     } elsif ($targets->[$targetindex][17] == 3) {
		                ($targets->[$targetindex][5]=&findIndexByMac) || return(0);
		     } elsif ($targets->[$targetindex][17] == 4) {
		                ($targets->[$targetindex][5]=&findIndexByIp) || return(0);
		     }
	     } else {
		     print("findInterfaceIndex() Warning: could not get OIDIfIndexTable for target $targets->[$targetindex][0]: ", $session->error(),"\n");
		     return(0);
	     }
     }
}
                                                                                                 

##########################################
# findIndexByName(): gets the interface index number by the name (description) of it
# Arguments: 
# 	none
# Returns: 
# 	the index of the interface if found, 0 if not found

sub findIndexByName {
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

##########################################
# findIndexByMac(): gets the interface index number by it's MAC
# Arguments: 
# 	none
# Returns: 
# 	the index of the interface if found, 0 if not found

sub findIndexByMac {
	my($macresponse)="";
	&debug("findIndexByMac(): Let's search for the mac address ($targets->[$targetindex][5])\n");
	my $OIDMacTable = '.1.3.6.1.2.1.2.2.1.6';
	defined($macresponse=$session->get_table($OIDMacTable)) || (print("findIndexByMac() Fatal: ", $session->error()) && return(0)); 
        if ($targets->[$targetindex][5] !~ /0x[a-z,0-9]{12}/i) { # if the mac is not in the SNMP default format 0xMAC
         	$targets->[$targetindex][5] =~ s/://g;  # we remove the :
                $targets->[$targetindex][5] = "0x".$targets->[$targetindex][5]; # append a "0x" string on it
        } # now we have the default SNMP format MAC
	foreach (&Net::SNMP::oid_lex_sort(keys(%{$response}))) {
		my($ifnum)=sprintf("%d", $response->{$_});
		my($mac)=sprintf("%s", $macresponse->{"$OIDMacTable.$ifnum"});
		if ($mac =~ / *$targets->[$targetindex][5] */) {
			&debug("findIndexByMac(): InterfaceMAC: $targets->[$targetindex][5] Index: $ifnum\n");
			return($ifnum);
		}
	}
	print("findIndexByMac() Warning: Mac ($targets->[$targetindex][5]) NOT found\n");
	return(0);
}



########################################
# findIndexByIp(): gets the interface index number using it's IP
# Arguments: 
# 	none
# Returns: 
# 	the index of the interface if found, 0 if not found

sub findIndexByIp {
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
