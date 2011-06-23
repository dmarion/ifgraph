# -*- mode: perl -*-
# ============================================================================

package Net::SNMP;

# $Id: SNMP_365.pm,v 1.1.1.1 2003/06/11 19:33:42 sartori Exp $
# $Source: /usr/local/cvsroot/ifgraph-0.4.10/lib/Net/SNMP_365.pm,v $

# The module Net::SNMP implements an object oriented interface to the Simple
# Network Management Protocol.  Perl applications can use the module to 
# retrieve or update information on a remote host using the SNMP protocol.
# Both SNMPv1 and SNMPv2c (Community-Based SNMPv2) are supported by the 
# module.  The Net::SNMP module assumes that the user has a basic 
# understanding of the Simple Network Management Protocol and related 
# network management concepts.

# Copyright (c) 1998-2001 David M. Town <david.town@marconi.com>.
# All rights reserved.

# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself.

# ============================================================================

## Global variables 

use vars qw(
   @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS @ASN1 @ASN1_PDU @GENERICTRAP @SNMP 
   @TRANSLATE $DEBUG $FSM $REQUEST_ID $SOCKET $VERSION  
);

## Version of Net::SNMP module

$Net::SNMP::VERSION = 3.65;

use strict;

## Required version of Perl

require 5.004;

## Handle exporting of symbols

use Exporter();

@ISA = qw(Exporter);

@ASN1 = qw(
   INTEGER INTEGER32 OCTET_STRING NULL OBJECT_IDENTIFIER IPADDRESS  
   COUNTER COUNTER32 GAUGE GAUGE32 UNSIGNED32 TIMETICKS OPAQUE 
   COUNTER64 NOSUCHOBJECT NOSUCHINSTANCE ENDOFMIBVIEW 
);

@ASN1_PDU = qw(
   GET_REQUEST GET_NEXT_REQUEST GET_RESPONSE SET_REQUEST TRAP
   GET_BULK_REQUEST INFORM_REQUEST SNMPV2_TRAP
);

@GENERICTRAP = qw(
   COLD_START WARM_START LINK_DOWN LINK_UP AUTHENTICATION_FAILURE 
   EGP_NEIGHBOR_LOSS ENTERPRISE_SPECIFIC 
);

@SNMP = qw(
   SNMP_VERSION_1 SNMP_VERSION_2C SNMP_PORT SNMP_TRAP_PORT snmp_debug 
   oid_context_match oid_lex_sort ticks_to_time 
);

@TRANSLATE = qw(
   TRANSLATE_NONE TRANSLATE_OCTET_STRING TRANSLATE_NULL TRANSLATE_TIMETICKS
   TRANSLATE_OPAQUE TRANSLATE_NOSUCHOBJECT TRANSLATE_NOSUCHINSTANCE
   TRANSLATE_ENDOFMIBVIEW TRANSLATE_UNSIGNED TRANSLATE_ALL
);

@EXPORT    = (@ASN1, 'snmp_event_loop');
@EXPORT_OK = (
   @ASN1_PDU, @GENERICTRAP, @SNMP, @TRANSLATE, 'SEQUENCE', 'snmp_one_event'
);

%EXPORT_TAGS = (
   asn1        => [@ASN1, @ASN1_PDU, 'SEQUENCE'],
   generictrap => [@GENERICTRAP], 
   snmp        => [@SNMP, 'snmp_event_loop'],
   translate   => [@TRANSLATE],
   ALL         => [@EXPORT, @EXPORT_OK]
);

## Import socket() defines and structure manipulators

use Socket qw(PF_INET SOCK_DGRAM inet_aton inet_ntoa sockaddr_in);

sub IPPROTO_UDP()         {   17 }

## ASN.1 Basic Encoding Rules type definitions

sub INTEGER()             { 0x02 }  # INTEGER      
sub INTEGER32()           { 0x02 }  # Integer32           - SNMPv2c
sub OCTET_STRING()        { 0x04 }  # OCTET STRING
sub NULL()                { 0x05 }  # NULL       
sub OBJECT_IDENTIFIER()   { 0x06 }  # OBJECT IDENTIFIER  
sub SEQUENCE()            { 0x30 }  # SEQUENCE       

sub IPADDRESS()           { 0x40 }  # IpAddress     
sub COUNTER()             { 0x41 }  # Counter  
sub COUNTER32()           { 0x41 }  # Counter32           - SNMPv2c 
sub GAUGE()               { 0x42 }  # Gauge     
sub GAUGE32()             { 0x42 }  # Gauge32             - SNMPv2c
sub UNSIGNED32()          { 0x42 }  # Unsigned32          - SNMPv2c 
sub TIMETICKS()           { 0x43 }  # TimeTicks  
sub OPAQUE()              { 0x44 }  # Opaque   
sub COUNTER64()           { 0x46 }  # Counter64           - SNMPv2c 

sub NOSUCHOBJECT()        { 0x80 }  # noSuchObject        - SNMPv2c 
sub NOSUCHINSTANCE()      { 0x81 }  # noSuchInstance      - SNMPv2c 
sub ENDOFMIBVIEW()        { 0x82 }  # endOfMibView        - SNMPv2c 
 
sub GET_REQUEST()         { 0xa0 }  # GetRequest-PDU    
sub GET_NEXT_REQUEST()    { 0xa1 }  # GetNextRequest-PDU 
sub GET_RESPONSE()        { 0xa2 }  # GetResponse-PDU
sub SET_REQUEST()         { 0xa3 }  # SetRequest-PDU
sub TRAP()                { 0xa4 }  # Trap-PDU
sub GET_BULK_REQUEST()    { 0xa5 }  # GetBulkRequest-PDU  - SNMPv2c 
sub INFORM_REQUEST()      { 0xa6 }  # InformRequest-PDU   - SNMPv2c 
sub SNMPV2_TRAP()         { 0xa7 }  # SNMPv2-Trap-PDU     - SNMPv2c 

## SNMP generic definitions 

sub SNMP_VERSION_1()      { 0x00 }  # RFC 1157 SNMP
sub SNMP_VERSION_2C()     { 0x01 }  # RFCs 1901, 1905, and 1906 SNMPv2c 
sub SNMP_PORT()           {  161 }  # RFC 1157 standard UDP port for PDUs
sub SNMP_TRAP_PORT()      {  162 }  # RFC 1157 standard UDP port for Trap-PDUs

## RFC 1157 generic-trap definitions

sub COLD_START()             { 0 }  # coldStart(0)
sub WARM_START()             { 1 }  # warmStart(1)
sub LINK_DOWN()              { 2 }  # linkDown(2)
sub LINK_UP()                { 3 }  # linkUp(3)
sub AUTHENTICATION_FAILURE() { 4 }  # authenticationFailure(4)
sub EGP_NEIGHBOR_LOSS()      { 5 }  # egpNeighborLoss(5)
sub ENTERPRISE_SPECIFIC()    { 6 }  # enterpriseSpecific(6)

## Translation masks

sub TRANSLATE_NONE()           { 0x00 }  # Bit masks used to determine
sub TRANSLATE_OCTET_STRING()   { 0x01 }  # if a specific ASN.1 type is
sub TRANSLATE_NULL()           { 0x02 }  # translated into a "human
sub TRANSLATE_TIMETICKS()      { 0x04 }  # readable" form.
sub TRANSLATE_OPAQUE()         { 0x08 }
sub TRANSLATE_NOSUCHOBJECT()   { 0x10 }
sub TRANSLATE_NOSUCHINSTANCE() { 0x20 }
sub TRANSLATE_ENDOFMIBVIEW()   { 0x40 }
sub TRANSLATE_UNSIGNED()       { 0x80 }
sub TRANSLATE_ALL()            { 0xff }

## Default, minimum, and maximum values 

sub DEFAULT_HOSTNAME()    { 'localhost' }
sub DEFAULT_COMMUNITY()   {    'public' }

sub DEFAULT_MTU()         {  1500 } # Typical messsage size 
sub DEFAULT_TIMEOUT()     {   5.0 } # Timeout period for UDP in seconds
sub DEFAULT_RETRIES()     {     1 } # Number of retransmissions 

sub MINIMUM_MTU()         {   484 } # RFC 1157 minimum size in octets    
sub MINIMUM_TIMEOUT()     {   1.0 }   
sub MINIMUM_RETRIES()     {     0 }     

sub MAXIMUM_MTU()         { 65535 }
sub MAXIMUM_TIMEOUT()     {  60.0 }   
sub MAXIMUM_RETRIES()     {    20 }

## Internal constants 

sub TRUE()                     { 0x01 }  # Truth values
sub FALSE()                    { 0x00 }

sub GET_TABLE_MAX_REPETITIONS() {  10 }  # Constant for get_table() 

## Intialize global variables

sub BEGIN
{
   # Import symbol generating function
   use Symbol qw(gensym);

   $DEBUG      = FALSE;
   $FSM        = undef;
   $REQUEST_ID = int(rand 0xff) + (time() & 0xff);
   $SOCKET     = gensym();
}

# [public methods] -----------------------------------------------------------

sub new
{
   my ($class, %argv) = @_;

   # Create a new data structure for the object
   my $this = bless {
        '_buffer',        =>  "\0" x DEFAULT_MTU,
	'_callback'       =>  undef,
        '_community'      =>  DEFAULT_COMMUNITY,
        '_error'          =>  undef,
        '_error_index'    =>  0,
        '_error_status'   =>  0,
        '_fsm'            =>  undef,
        '_hostname'       =>  DEFAULT_HOSTNAME,
        '_leading_dot'    =>  FALSE,
        '_mtu'            =>  DEFAULT_MTU,
        '_nonblocking'    =>  FALSE,
        '_port'           =>  SNMP_PORT,
        '_request_id'     =>  $REQUEST_ID++,
        '_retries'        =>  DEFAULT_RETRIES,
        '_sockaddr'       =>  undef,
        '_socket'         =>  undef,
        '_type'           =>  undef,
        '_timeout'        =>  DEFAULT_TIMEOUT,
        '_translate'      =>  TRANSLATE_ALL,
        '_var_bind_list'  =>  undef,
        '_version'        =>  SNMP_VERSION_1
   }, $class;

   # Validate the passed arguments
   foreach (keys %argv) {
      if (/^-?community$/i) {
         if (!defined($argv{$_})) {
            $this->_object_error('community not defined');
         } else {
            $this->{'_community'} = $argv{$_};
         }
      } elsif (/^-?debug$/i) {
         $this->debug($argv{$_});
      } elsif (/^-?hostname$/i) {
         if ($argv{$_} eq '') {
            $this->_object_error('Empty hostname specified');
         } else {
            $this->{'_hostname'} = $argv{$_};
         }
      } elsif (/^-?mtu$/i) {
         $this->mtu($argv{$_});
      } elsif (/^-?nonblocking$/i) {
         if ($argv{$_}) {
            $this->{'_nonblocking'} = TRUE;
         } else {
            $this->{'_nonblocking'} = FALSE;
         }
      } elsif (/^-?port$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            $this->_object_error('Expected positive numeric port number');
         } else {
            $this->{'_port'} = $argv{$_};
         }
      } elsif (/^-?retries$/i) {
         $this->retries($argv{$_});
      } elsif (/^-?timeout$/i) {
         $this->timeout($argv{$_});
      } elsif (/^-?translate$/i) {
         $this->translate($argv{$_});
      } elsif (/^-?version$/i) {
         $this->version($argv{$_});
      } else {
         $this->_object_error("Invalid argument '%s'", $_);
      }
      if (defined($this->{'_error'})) {
         return wantarray ? (undef, $this->{'_error'}) : undef;
      }
   }

   # Create a global Net:SNMP::FSM object (if not created) when the 
   # object has the "non-blocking" flag set, and store a reference
   # to the Finite State Machine (FSM) within the object. 

   if ($this->{'_nonblocking'}) {
      if ((!defined($FSM)) || (ref($FSM) ne 'Net::SNMP::FSM')) {
         if (!defined($FSM = Net::SNMP::FSM->new())) {
            # You should never see this error!
            $this->_object_error(
               'Unable to create Net::SNMP Finite State Machine object'
            );
            return wantarray ? (undef, $this->{'_error'}) : undef;
         }
      }
      $this->{'_fsm'} = $FSM;
   }

   # Return the object and empty error message (in list context)
   wantarray ? ($this, '') : $this;
}

sub open 
{
   my $this = shift;
   my ($host_addr, $proto) = (undef, undef);
   
   # Resolve the hostname to an IP address
   if (!defined($host_addr = inet_aton($this->hostname))) {
      return $this->_object_error(
         "Unable to resolve hostname '%s'", $this->hostname
      );
   }

   # Pack the address and port information
   $this->{'_sockaddr'} = sockaddr_in($this->{'_port'}, $host_addr);

   # Open a global UDP socket for the package (if not open), and store
   # a reference to the socket within the object.
 
   if (!fileno($SOCKET)) {
      
      # Get the protocol number for UDP
      if (!defined($proto = scalar(getprotobyname('udp')))) {
         $proto = IPPROTO_UDP;
      }

      # Open the socket
      if (!socket($SOCKET, PF_INET, SOCK_DGRAM, $proto)) {
         return $this->_object_error("socket(): %s", $!);
      }

   }
   $this->{'_socket'} = $SOCKET;

   TRUE;
}

sub close
{
   my $this = shift;
   
   # Clear all of the buffers and errors
   $this->_object_clear_buffer;
   $this->_object_clear_var_bind_list;
   $this->_object_clear_error;

   # Clear the socket reference so that we can tell that this particular
   # object has been closed.

   $this->{'_socket'} = undef;

   TRUE;
}

sub session
{
   my $class = shift;

   # This is a convenience method (also present for backwards compatiblity),
   # that just combines the new() and the open() methods into one method.

   my ($this, $error) = $class->new(@_);

   if (defined($this)) { 
      if (!defined($this->open)) { 
         return wantarray ? (undef, $this->error) : undef; 
      }
   }

   wantarray ? ($this, $error) : $this; 
}

sub snmp_event_loop 
{ 
   ref($FSM) eq 'Net::SNMP::FSM' ? $FSM->event_loop : undef;
}

sub snmp_one_event
{ 
   ref($FSM) eq 'Net::SNMP::FSM' ? $FSM->one_event : undef;
}

sub get_request
{
   my $this = shift;

   # Handle passed arguments according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;
      my @var_bind_list = ();

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?callback$/i) {
            if (!defined($this->_object_add_callback($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?varbindlist$/i) {
            if (ref($argv{$_}) ne 'ARRAY') {
               return $this->_object_error(
                  'Expected array reference for variable-bindings'
               );
            } else {
               @var_bind_list = @{$argv{$_}};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Encode and queue the message
      if (!defined($this->_snmp_encode_get_request(@var_bind_list))) {
         return $this->_object_encode_error;
      }
      $this->_object_queue_message;

   } else {

      # Encode, send and wait, and decode the message
      if (!defined($this->_snmp_encode_get_request(@_))) { 
         return $this->_object_encode_error; 
      }
      $this->_snmp_send_and_validate;

   }
}

sub get_next_request
{
   my $this = shift;

   # Handle passed arguments according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;
      my @var_bind_list = ();

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?callback$/i) {
            if (!defined($this->_object_add_callback($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?varbindlist$/i) {
            if (ref($argv{$_}) ne 'ARRAY') {
               return $this->_object_error(
                  'Expected array reference for variable-bindings'
               );
            } else {
               @var_bind_list = @{$argv{$_}};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Encode and queue the message
      if (!defined($this->_snmp_encode_get_next_request(@var_bind_list))) {
         return $this->_object_encode_error;
      }
      $this->_object_queue_message;

   } else {

      # Encode, send and wait, and decode the message
      if (!defined($this->_snmp_encode_get_next_request(@_))) {
         return $this->_object_encode_error;
      }
      $this->_snmp_send_and_validate;

   }
}

sub set_request
{
   my $this = shift;

   # Handle passed arguments according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;
      my @var_bind_list = ();

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?callback$/i) {
            if (!defined($this->_object_add_callback($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?varbindlist$/i) {
            if (ref($argv{$_}) ne 'ARRAY') {
               return $this->_object_error(
                  'Expected array reference for variable-bindings'
               );
            } else {
               @var_bind_list = @{$argv{$_}};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Encode and queue the message
      if (!defined($this->_snmp_encode_set_request(@var_bind_list))) {
         return $this->_object_encode_error;
      }
      $this->_object_queue_message;

   } else {

      # Encode, send and wait, and decode the message
      if (!defined($this->_snmp_encode_set_request(@_))) {
         return $this->_object_encode_error;
      }
      $this->_snmp_send_and_validate;

   }
}

sub trap
{
   my ($this, %argv) = @_;

   # Clear any previous error message
   $this->_object_clear_error;

   # Use Sys:Hostname to determine the IP address of the client sending
   # the trap.  Only require the module for Trap-PDUs.

   use Sys::Hostname();

   # Setup default values for the Trap-PDU by creating new entries in 
   # the Net::SNMP object.

   # Use iso.org.dod.internet.private.enterprises for the default enterprise. 
   $this->{'_enterprise'} = '1.3.6.1.4.1';  

   # Create an entry for the agent-addr (we will fill it in below if
   # if the user does not specify an address)
   $this->{'_agent_addr'} = undef;

   # Use enterpriseSpecific(6) for the generic-trap type.
   $this->{'_generic_trap'} = ENTERPRISE_SPECIFIC;

   # Set the specific-trap type to 0.
   $this->{'_specific_trap'} = 0;

   # Use the "uptime" of the script for the time-stamp.
   $this->{'_time_stamp'} = ((time() - $^T) * 100);

   # Create a local copy of the VarBindList.
   my @var_bind_list = ();


   # Validate the passed arguments
   foreach (keys %argv) {
      if (/^-?enterprise$/i) {
         if ($argv{$_} !~ /^\.?\d+\.\d+(\.\d+)*/) {
            return $this->_object_error(
               'Expected enterprise as OBJECT IDENTIFIER in dotted notation' 
            );
         } else {
            $this->{'_enterprise'} = $argv{$_};
         }
      } elsif (/^-?agentaddr$/i) {
         if ($argv{$_} !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
            return $this->_object_error(
               'Expected agent-addr in dotted notation'     
            );
         } else {
            $this->{'_agent_addr'} = $argv{$_};
         }
      } elsif (/^-?generictrap$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            return $this->_object_error(
               'Expected positive numeric generic-trap type'
            );
         } else {
            $this->{'_generic_trap'} = $argv{$_};
         }
      } elsif (/^-?specifictrap$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            return $this->_object_error(
               'Expected positive numeric specific-trap type'
            );
         } else {
            $this->{'_specific_trap'} = $argv{$_};
         }
      } elsif (/^-?timestamp$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            return $this->_object_error('Expected positive numeric time-stamp');
         } else {
            $this->{'_time_stamp'} = $argv{$_};
         }
      } elsif (/^-?varbindlist$/i) {
         if (ref($argv{$_}) ne 'ARRAY') {
            return $this->_object_error(
               'Expected array reference for variable-bindings'
            );
         } else {
            @var_bind_list = @{$argv{$_}}; 
         }   
      } elsif ((/^-?delay$/i) && ($this->{'_nonblocking'})) {
         if (!defined($this->_object_event_delay($argv{$_}))) {
            return $this->_object_error;
         }
      } else {
         return $this->_object_error("Invalid argument '%s'", $_);
      }
   }

   # If the user did not specify the agent-addr, get local the address 
   # of the client sending the trap. 

   if (!defined($this->{'_agent_addr'})) {
      eval {
         $this->{'_agent_addr'} = inet_ntoa(
            scalar(gethostbyname(&Sys::Hostname::hostname()))
         );
      };
      if ($@ ne '') {
         return $this->_object_encode_error(
            'Unable to resolve local agent-addr'
         );
      }
   }

   if (!defined($this->_snmp_encode_trap(@var_bind_list))) {
      return $this->_object_encode_error;
   }

   # Handle the sending of the message according to "blocking" mode

   if ($this->{'_nonblocking'}) {
      $this->_object_queue_message;
   } else {
      $this->_udp_send_buffer;
   }
}

sub get_bulk_request
{
   my ($this, %argv) = @_;

   # Clear any previous error message which also clears the 
   # '_error_status' and '_error_index' so that we can use them 
   # to hold non-repeaters and max-repetitions.  
  
   $this->_object_clear_error;

   # Validate the SNMP version
   if ($this->version == SNMP_VERSION_1) {
      return $this->_object_error(
         'GetBulkRequest-PDU not supported in SNMPv1'
      );
   }

   # Create a local copy of the VarBindList.
   my @var_bind_list = ();

   # Validate the passed arguments
   foreach (keys %argv) {
      if (/^-?nonrepeaters$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            return $this->_object_error(
               'Expected positive numeric non-repeaters value'
            );
         } elsif ($argv{$_} > 2147483647) {
            return $this->_object_error(
               'Exceeded maximum non-repeaters value [2147483647]'
            );
         } else {
            # We cheat a little here...
            $this->{'_error_status'} = $argv{$_};
         }
      } elsif (/^-?maxrepetitions$/i) {
         if ($argv{$_} !~ /^\d+$/) {
            return $this->_object_error(
               'Expected positive numeric max-repetitions value'
            );
         } elsif ($argv{$_} > 2147483647) {
            return $this->_object_error(
               'Exceeded maximum max-repetitions value [2147483647]'
            );
         } else {
            # We cheat a little here...
            $this->{'_error_index'} = $argv{$_};
         }
      } elsif (/^-?varbindlist$/i) {
         if (ref($argv{$_}) ne 'ARRAY') {
            return $this->_object_error(
               'Expected array reference for variable-bindings'
            );
         } else {
            @var_bind_list = @{$argv{$_}};
         }
      } elsif ((/^-?callback$/i) && ($this->{'_nonblocking'})) {
         if (!defined($this->_object_add_callback($argv{$_}))) {
            return $this->_object_error;
         }
      } elsif ((/^-?delay$/i) && ($this->{'_nonblocking'})) {
         if (!defined($this->_object_event_delay($argv{$_}))) {
            return $this->_object_error;
         }
      } else {
         return $this->_object_error("Invalid argument '%s'", $_);
      }
   }

   if ($this->{'_error_status'} > scalar(@var_bind_list)) {
      return $this->_object_error(
         'Non-repeaters greater than the number of variable-bindings'
      );
   }

   if (($this->{'_error_status'} == scalar(@var_bind_list)) &&
       ($this->{'_error_index'} != 0))
   {
      return $this->_object_error(
         'Non-repeaters equals the number of variable-bindings and ' .
         'max-repetitions is not equal to zero'
      );
   }

   if (!defined($this->_snmp_encode_get_bulk_request(@var_bind_list))) {
      return $this->_object_encode_error;
   }

   # Handle the sending of the message according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      # Queue the message
      $this->_object_queue_message;

   } else {

      # Send and wait
      $this->_snmp_send_and_validate;
   }
}

sub inform_request
{
   my $this = shift;
  
   # Clear any previous error message
   $this->_object_clear_error;

   # Validate the SNMP version
   if ($this->version == SNMP_VERSION_1) {
      return $this->_object_error(
         'InformRequest-PDU not supported in SNMPv1'
      );
   }
 
   # Handle passed arguments according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;
      my @var_bind_list = ();

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?callback$/i) {
            if (!defined($this->_object_add_callback($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?varbindlist$/i) {
            if (ref($argv{$_}) ne 'ARRAY') {
               return $this->_object_error(
                  'Expected array reference for variable-bindings'
               );
            } else {
               @var_bind_list = @{$argv{$_}};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Encode and queue the message
      if (!defined($this->_snmp_encode_inform_request(@var_bind_list))) {
         return $this->_object_error;
      }
      $this->_object_queue_message;

   } else {

      # Encode, send/wait, and decode the message
      if (!defined($this->_snmp_encode_inform_request(@_))) {
         return $this->_object_encode_error;
      }
      $this->_snmp_send_and_validate;

   }
}

sub snmpv2_trap 
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Validate the SNMP version
   if ($this->version == SNMP_VERSION_1) {
      return $this->_object_error(
         'SNMPv2-Trap-PDU not supported in SNMPv1'
      );
   }

   # Handle passed arguments according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;
      my @var_bind_list = ();

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?varbindlist$/i) {
            if (ref($argv{$_}) ne 'ARRAY') {
               return $this->_object_error(
                  'Expected array reference for variable-bindings'
               );
            } else {
               @var_bind_list = @{$argv{$_}};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Encode the message
      if (!defined($this->_snmp_encode_v2_trap(@var_bind_list))) {
         return $this->_object_encode_error;
      }

      # Queue the message
      $this->_object_queue_message;

   } else {

      # Encode the message
      if (!defined($this->_snmp_encode_v2_trap(@_))) {
         return $this->_object_encode_error;
      }

      # Send the message
      $this->_udp_send_buffer;
   }
}

sub get_table
{
   my $this = shift;
   my $base_oid;

   # Use get-next-requests or get-bulk-requests until the response is 
   # not a subtree of the base OBJECT IDENTIFIER.  Return the table only 
   # if there are no errors other than a noSuchName(2) error since the 
   # table could be at the end of the tree.  Also return the table when 
   # the value of the OID equals endOfMibView(2) when using SNMPv2c.
  
   # Handle passed argument according to "blocking" mode

   if ($this->{'_nonblocking'}) {

      my %argv = @_;

      # Validate the passed arguments
      foreach (keys %argv) {
         if (/^-?callback$/i) {
            if (!defined($this->_object_add_callback($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?delay$/i) {
            if (!defined($this->_object_event_delay($argv{$_}))) {
               return $this->_object_error;
            }
         } elsif (/^-?baseoid$/i) {
            if ($argv{$_} !~ /^\.?\d+\.\d+(\.\d+)*/) {
               return $this->_object_error(
                  'Expected base OBJECT IDENTIFIER in dotted notation'
               );
            } else {
               $base_oid = $argv{$_};
            }
         } else {
            return $this->_object_error("Invalid argument '%s'", $_);
         }
      }

      # Create table of values that need passed along with the
      # callbacks.  This just prevents a big argument list.

      %argv = (
         'base_oid'   => $base_oid,
         'callback'   => $this->{'_callback'},
         'repeat_cnt' => 0,
         'table'      => undef,
      );

      # Queue up the get-next-request or get-bulk_request, overriding the 
      # user-specified callback.  We have the original in the arguments.

      if ($this->version == SNMP_VERSION_1) {
         $this->get_next_request(
            -callback    => [\&_object_get_table_cb, \%argv],
            -varbindlist => [$base_oid]
         );
      } else {
         $this->get_bulk_request(
            -callback       => [\&_object_get_table_cb, \%argv],
            -maxrepetitions => GET_TABLE_MAX_REPETITIONS,
            -varbindlist    => [$base_oid]
         );
      }

   } else {

      my $next_oid = $base_oid = shift(@_);
      my ($result, $repeat_cnt, $table) = (undef, 0, undef);
      my ($end_of_table, @oids) = (FALSE);

      do {

         # Add the OBJECT IDENTIFIER to the table

         if (defined($result)) {
            if (!exists($table->{$next_oid})) {
               $table->{$next_oid} = $result->{$next_oid};
            } elsif (($result->{$next_oid} eq 'endOfMibView')      # translate 
                     || (($result->{$next_oid} eq '')              # !translate 
                        && ($this->error_status == ENDOFMIBVIEW)))
            {
               $this->_object_clear_error;
               $end_of_table = TRUE;
            } else {
               $repeat_cnt++;
            }
         }

         # Check to make sure that the remote host does not respond
         # incorrectly causing the get-next-requests to loop forever.

         if ($repeat_cnt > 5) {
            return $this->_object_decode_error(
               'Loop detected with table on remote host'
            );
         }

         # Build the table by sending get-next-requests or get-bulk-requests
         # depending on the SNMP version.

         if ((@oids == 0) && (!$end_of_table)) {
         
            if ($this->version == SNMP_VERSION_1) {
               if (!defined($result = $this->get_next_request($next_oid))) {
                  # Check for noSuchName(2) error 
                  if ($this->error_status == 2) { 
                     $this->_object_clear_error;
                     $end_of_table = TRUE; 
                  } else {
                     return $this->_object_decode_error;
                  }
               }
            } else {
               $result = $this->get_bulk_request(
                  -maxrepetitions => GET_TABLE_MAX_REPETITIONS,
                  -varbindlist    => [$next_oid]
               );
               if (!defined($result)) {
                  return $this->_object_decode_error;
               }
            }

            @oids = oid_lex_sort(keys(%{$result}));
         }
 
         $next_oid = shift(@oids);

      } while (_asn1_oid_context_match($base_oid, $next_oid)); 

      if (!defined($table)) {
         $this->_object_decode_error(
            'Requested table is empty or does not exist'
         );
      }

      $this->{'_var_bind_list'} = $table;
   }
}

sub error 
{ 
   defined($_[0]->{'_error'}) ? $_[0]->{'_error'} : ''; 
}

sub version
{
   my ($this, $version) = @_;

   # Clear any previous error message
   $this->_object_clear_error;

   # Allow the user some flexability
   my $supported = {
      '1'       => SNMP_VERSION_1,
      'v1'      => SNMP_VERSION_1,
      'snmpv1'  => SNMP_VERSION_1,
      '2'       => SNMP_VERSION_2C,
      '2c'      => SNMP_VERSION_2C,
      'v2'      => SNMP_VERSION_2C,
      'v2c'     => SNMP_VERSION_2C,
      'snmpv2'  => SNMP_VERSION_2C,
      'snmpv2c' => SNMP_VERSION_2C,
   };

   if (@_ == 2) {
      if (exists($supported->{lc($version)})) {
         $this->{'_version'} = $supported->{lc($version)};
      } else {
         return $this->_object_error(
            "Unknown or invalid SNMP version [%s]", $version
         );
      }
   }

   $this->{'_version'};
}

sub hostname      
{ 
   $_[0]->{'_hostname'};      
} 

sub error_status  
{ 
   $_[0]->{'_error_status'};  
}

sub error_index   
{ 
   $_[0]->{'_error_index'};   
}

sub var_bind_list 
{ 
   $_[0]->{'_var_bind_list'}; 
}

sub timeout
{
   # Clear any previous error message
   $_[0]->_object_clear_error;

   if (@_ == 2) {
      if ($_[1] =~ /^\d+(\.\d+)?$/) {
         if (($_[1] >= MINIMUM_TIMEOUT) && ($_[1] <= MAXIMUM_TIMEOUT)) { 
            $_[0]->{'_timeout'} = $_[1]; 
         } else {
            return $_[0]->_object_encode_error(
               "Timeout out of range [%03.01f - %03.01f seconds]",
               MINIMUM_TIMEOUT, MAXIMUM_TIMEOUT
            );
         }
      } else {
         return $_[0]->_object_encode_error(
            'Expected positive numeric timeout value'
         );
      } 
   }

   $_[0]->{'_timeout'};
}

sub retries 
{
   # Clear any previous error message
   $_[0]->_object_clear_error;

   if (@_ == 2) {
      if ($_[1] =~ /^\d+$/) {
         if (($_[1] >= MINIMUM_RETRIES) && ($_[1] <= MAXIMUM_RETRIES)) { 
            $_[0]->{'_retries'} = $_[1]; 
         } else {
            return $_[0]->_object_encode_error(
               "Retries out of range [%d - %d]", 
               MINIMUM_RETRIES, MAXIMUM_RETRIES
            );
         }
      } else {
         return $_[0]->_object_encode_error(
            'Expected positive numeric retries value'
         );
      }
   }

   $_[0]->{'_retries'};
}

sub mtu 
{
   # Clear any previous error message
   $_[0]->_object_clear_error;

   if (@_ == 2) {
      if ($_[1] =~ /^\d+$/) {
         if (($_[1] >= MINIMUM_MTU) && ($_[1] <= MAXIMUM_MTU )) { 
            $_[0]->{'_mtu'} = $_[1]; 
         } else {
            return $_[0]->_object_encode_error(
               "MTU out of range [%d - %d octets]", MINIMUM_MTU, MAXIMUM_MTU
            );
         }
      } else {
         return $_[0]->_object_encode_error(
            'Expected positive numeric MTU value'
         );
      }
   }

   $_[0]->{'_mtu'};
}

sub translate
{
   # Clear any previous error message
   $_[0]->_object_clear_error;
 
   if (@_ == 2) {

      if (ref($_[1]) ne 'ARRAY') {
 
         # Behave like we did before, do (not) translate everything
         $_[0]->_object_translate_mask($_[1], TRANSLATE_ALL);

      } else {

         # Allow the user to turn off and on specific translations.  An
         # array is used so the order of the arguments controls how the
         # mask is defined.

         my @argv = @{$_[1]};
         my $type;

         while (defined($type = shift(@argv))) {
            if ($type =~ /^-?all$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_ALL);
            } elsif ($type =~ /^-?none$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_NONE);
            } elsif ($type =~ /^-?octet_?string$/i) {
               $_[0]->_object_translate_mask(
                  shift(@argv), TRANSLATE_OCTET_STRING
               );
            } elsif ($type =~ /^-?null$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_NULL);
            } elsif ($type =~ /^-?timeticks$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_TIMETICKS);
            } elsif ($type =~ /^-?opaque$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_OPAQUE);
            } elsif ($type =~ /^-?nosuchobject$/i) {
               $_[0]->_object_translate_mask(
                  shift(@argv), TRANSLATE_NOSUCHOBJECT
               );
            } elsif ($type =~ /^-?nosuchinstance$/i) {
               $_[0]->_object_translate_mask(
                  shift(@argv), TRANSLATE_NOSUCHINSTANCE
               ); 
            } elsif ($type =~ /^-?endofmibview$/i) {
               $_[0]->_object_translate_mask(
                  shift(@argv), TRANSLATE_ENDOFMIBVIEW
               );
            } elsif ($type =~ /^-?unsigned$/i) {
               $_[0]->_object_translate_mask(shift(@argv), TRANSLATE_UNSIGNED);
            } else {
               return $_[0]->_object_error( 
                  "Invalid translate argument '%s'", $type
               );
            }
         }

      }

      DEBUG_INFO("translate = 0x%02x", $_[0]->{'_translate'});
   }

   $_[0]->{'_translate'};
}

sub debug
{
   if (@_ == 2) {
      if ($_[1]) {
         $Net::SNMP::DEBUG = TRUE;
      } else {
         $Net::SNMP::DEBUG = FALSE;
      }
   }

   $Net::SNMP::DEBUG;  
}

sub END 
{
   if (defined($SOCKET)) { 
      if (fileno($SOCKET)) { CORE::close($SOCKET); } 
   }
}


## Utility functions

sub snmp_debug($)         
{ 
   &Net::SNMP::debug(undef, $_[0]);         
}

sub oid_context_match($$) 
{ 
   &Net::SNMP::_asn1_oid_context_match($_[0], $_[1]); 
}

sub oid_lex_sort(@)       
{ 
   &Net::SNMP::_asn1_oid_lex_sort(@_);      
}

sub ticks_to_time($)      
{ 
   &Net::SNMP::_asn1_ticks_to_time($_[0]);  
}


# [private methods] ----------------------------------------------------------


###
## Simple Network Managment Protocol (SNMP) encode methods
###

sub _snmp_encode_get_request
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Check for a valid VarBindList
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); }  

   $this->_snmp_encode(GET_REQUEST, $this->_snmp_create_oid_null_pairs(@_));
}

sub _snmp_encode_get_next_request
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Check for a valid VarBindList
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); }

   $this->_snmp_encode(
      GET_NEXT_REQUEST, $this->_snmp_create_oid_null_pairs(@_)
   );
}

sub _snmp_encode_get_response
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   $this->_snmp_encode_error('GetResponse-PDU not supported');
}


sub _snmp_encode_set_request
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Check for a valid VarBindList
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); }

   $this->_snmp_encode(SET_REQUEST, $this->_snmp_create_oid_value_pairs(@_));
}

sub _snmp_encode_trap
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   $this->_snmp_encode(TRAP, $this->_snmp_create_oid_value_pairs(@_));
}

sub _snmp_encode_get_bulk_request
{
   my $this = shift;

   # DO NOT clear any previous error message or the non-repeaters
   # and the max-repetitions will be reset!

   # Check for a valid VarBindList
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); } 

   $this->_snmp_encode(
      GET_BULK_REQUEST, $this->_snmp_create_oid_null_pairs(@_)
   );
}

sub _snmp_encode_inform_request
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Check for a valid VarBindList
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); }

   $this->_snmp_encode(INFORM_REQUEST, $this->_snmp_create_oid_value_pairs(@_));
}

sub _snmp_encode_v2_trap
{
   my $this = shift;

   # Clear any previous error message
   $this->_object_clear_error;

   # Check for a valid VarBindList (or is that legal with a snmpV2-trap?)
   if (@_ < 1) { return $this->_snmp_encode_error('VarBindList is empty'); }

   $this->_snmp_encode(SNMPV2_TRAP, $this->_snmp_create_oid_value_pairs(@_));
} 

sub _snmp_encode
{
   my ($this, $type, @var_bind_list) = @_;
   
   # Do not do anything if there has already been an error
   if (defined($this->{'_error'})) { return $this->_snmp_encode_error; }

   # We need to reset the buffer that might have been defined
   # from a previous message and clear the var_bind_list.

   $this->_object_clear_buffer;
   $this->_object_clear_var_bind_list;
   $this->_object_clear_leading_dot;

   # Make sure the PDU type was passed
   if ((scalar(@_) < 2) || (!defined($type))) {
      return $this->_snmp_encode_error('No SNMP PDU type defined');
   } 
   $this->{'_type'} = $type;

   # Increment the global request-id and store it locally 
   $this->{'_request_id'} = $REQUEST_ID++; 
    
   # Encode the variable-bindings
   if (!defined($this->_snmp_encode_var_bind_list(@var_bind_list))) {
      return $this->_snmp_encode_error;
   }

   # Encode the PDU or Trap-PDU
   if ($this->{'_type'} == TRAP) {
      if (!defined($this->_snmp_encode_trap_pdu)) {
         return $this->_snmp_encode_error;
      }
   } else {
      if (!defined($this->_snmp_encode_pdu)) {
         return $this->_snmp_encode_error;
      }
   } 

   # Now wrap the message
   $this->_snmp_encode_message;
}

sub _snmp_encode_message
{
   my $this = shift;

   # We need to encode eveything in reverse order so the
   # objects end up in the correct place.

   # Encode the PDU type
   if (!defined(
         $this->_asn1_encode($this->{'_type'}, $this->_object_get_buffer)
      )) 
   { 
      return $this->_snmp_encode_error; 
   }

   # Encode the community name
   if (!defined($this->_asn1_encode(OCTET_STRING, $this->{'_community'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the SNMP version
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_version'}))) {
      return $this->_snmp_encode_error;
   } 

   # Encode the SNMP message SEQUENCE 
   if (!defined($this->_asn1_encode(SEQUENCE, $this->_object_get_buffer))) {
      return $this->_snmp_encode_error;
   } 

   # Return the buffer
   $this->{'_buffer'};
}
 
sub _snmp_encode_pdu
{
   my $this = shift;

   # We need to encode eveything in reverse order so the 
   # objects end up in the correct place.

   # Encode the error-index or max-repetitions (GetBulkRequest-PDU)  
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_error_index'}))) {
      return $this->_snmp_encode_error;
   } 
   
   # Encode the error-status or non-repeaters (GetBulkRequest-PDU) 
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_error_status'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the request-id [incremented in _snmp_encode()]  
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_request_id'}))) {
      return $this->_snmp_encode_error;
   }
 
   # Return the buffer 
   $this->{'_buffer'}; 
}

sub _snmp_encode_trap_pdu
{
   my $this = shift;

   # We need to encode eveything in reverse order so the
   # objects end up in the correct place.

   # Encode the time-stamp
   if (!defined($this->_asn1_encode(TIMETICKS, $this->{'_time_stamp'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the specific-trap type
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_specific_trap'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the generic-trap type
   if (!defined($this->_asn1_encode(INTEGER, $this->{'_generic_trap'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the agent-addr
   if (!defined($this->_asn1_encode(IPADDRESS, $this->{'_agent_addr'}))) {
      return $this->_snmp_encode_error;
   }

   # Encode the enterprise
   if (!defined(
         $this->_asn1_encode(OBJECT_IDENTIFIER, $this->{'_enterprise'})
      )) 
   { 
      return $this->_snmp_encode_error;
   }

   # Return the buffer
   $this->{'_buffer'};
}

sub _snmp_encode_var_bind_list
{
   my ($this, @var_bind) = @_;
   my ($type, $value) = (undef, '');

   # The passed array is expected to consist of groups of four values
   # consisting of two sets of ASN.1 types and their values.

   if ((scalar(@var_bind) % 4)) {
      return $this->_snmp_encode_error(
         "Invalid number of VarBind parameters [%d]", scalar(@var_bind) 
      );
   }
 
   # Encode the objects from the end of the list, so they are wrapped 
   # into the packet as expected.  Also, check to make sure that the 
   # OBJECT IDENTIFIER is in the correct place.

   my $buffer = $this->_object_get_buffer;

   while (@var_bind) {
      # Encode the ObjectSyntax
      $value = pop(@var_bind);
      $type  = pop(@var_bind);
      if (!defined($this->_asn1_encode($type, $value))) { 
         return $this->_snmp_encode_error; 
      }
      # Encode the ObjectName 
      $value = pop(@var_bind);
      $type  = pop(@var_bind);
      if ($type != OBJECT_IDENTIFIER) {
         return $this->_snmp_encode_error(
            'Expected OBJECT IDENTIFIER in VarBindList'
         );
      }
      if (!defined($this->_asn1_encode($type, $value))) {
         return $this->_snmp_encode_error;
      }
      # Encode the VarBind SEQUENCE 
      if (!defined($this->_asn1_encode(SEQUENCE, $this->_object_get_buffer))) {
         return $this->_snmp_encode_error;
      } 
      $buffer = join('', $this->_object_get_buffer, $buffer);
   } 

   # Encode the VarBindList SEQUENCE 
   if (!defined($this->_asn1_encode(SEQUENCE, $buffer))) { 
      return $this->_snmp_encode_error; 
   }

   # Return the buffer
   $this->{'_buffer'};
}

sub _snmp_create_oid_null_pairs
{
   my ($this, @oids) = @_;
   my ($oid) = (undef);
   my @pairs = ();

   while (defined($oid = shift(@oids))) {
      if ($oid !~ /^\.?\d+\.\d+(\.\d+)*/) {
         return $this->_snmp_encode_error(
            'Expected OBJECT IDENTIFIER in dotted notation'
         );
      }
      push(@pairs, OBJECT_IDENTIFIER, $oid, NULL, '');
   }

   @pairs;
}

sub _snmp_create_oid_value_pairs
{
   my ($this, @oid_values) = @_;
   my ($oid) = (undef);
   my @pairs = ();

   if ((scalar(@oid_values) % 3)) {
      return $this->_snmp_encode_error(
         'Expected [OBJECT IDENTIFIER, ASN.1 type, object value] combination'
      );
   }

   while (defined($oid = shift(@oid_values))) {
      if ($oid !~ /^\.?\d+\.\d+(\.\d+)*/) {
         return $this->_snmp_encode_error(
            'Expected OBJECT IDENTIFIER in dotted notation'
         );
      }
      push(@pairs, OBJECT_IDENTIFIER, $oid);
      push(@pairs, shift(@oid_values), shift(@oid_values));
   }

   @pairs;
}

sub _snmp_encode_error
{
   my $this = shift;

   # Clear the buffer
   $this->_object_clear_buffer;

   $this->_object_error(@_);
}


###
## Simple Network Managment Protocol (SNMP) decode methods
###

sub _snmp_decode_get_request      
{ 
   $_[0]->_snmp_decode(GET_REQUEST);      
}

sub _snmp_decode_get_next_request 
{ 
   $_[0]->_snmp_decode(GET_NEXT_REQUEST); 
}

sub _snmp_decode_get_response     
{ 
   $_[0]->_snmp_decode(GET_RESPONSE);     
}

sub _snmp_decode_set_request      
{ 
   $_[0]->_snmp_decode(SET_REQUEST);      
}

sub _snmp_decode_trap             
{ 
   $_[0]->_snmp_decode(TRAP);             
}

sub _snmp_decode_get_bulk_request 
{ 
   $_[0]->_snmp_decode(GET_BULK_REQUEST); 
}

sub _snmp_decode_inform_request   
{ 
   $_[0]->_snmp_decode(INFORM_REQUEST);   
} 

sub _snmp_decode_v2_trap          
{ 
   $_[0]->_snmp_decode(SNMPV2_TRAP);      
} 

sub _snmp_decode
{
   my ($this, $type) = @_;

   # First we need to reset the var_bind_list and errors that
   # might have been set from a previous message.

   $this->_object_clear_snmp_message;
   $this->_object_clear_var_bind_list;
   $this->_object_clear_error;

   # Define the message type to be decoded, if it was provided
   if (scalar(@_) > 1) { $this->{'_type'} = $type; } 

   # Decode the message
   if (!defined($this->_snmp_decode_message)) {
      return $this->_snmp_decode_error;
   }

   # Decode the PDU
   if ($this->{'_type'} != TRAP) {
      if (!defined($this->_snmp_decode_pdu)) { 
         return $this->_snmp_decode_error;
      }
   } else {
      if (!defined($this->_snmp_decode_trap_pdu)) { 
         return $this->_snmp_decode_error;
      }
   }

   # Decode the VarBindList
   $this->_snmp_decode_var_bind_list;
}

sub _snmp_decode_message
{
   my $this = shift;
   my $value = undef;

   # Decode the message SEQUENCE
   if (!defined($value = $this->_asn1_decode(SEQUENCE))) {
      return $this->_snmp_decode_error;
   } 
   if ($value != $this->_object_buffer_length) {
      return $this->_snmp_decode_error(
         'Encoded message length not equal to remaining data length' 
      );
   }

   # Decode the version
   if (!defined($this->{'_version'} = $this->_asn1_decode(INTEGER))) {
      return $this->_snmp_decode_error;
   } 

   # Decode the community
   if (!defined($this->{'_community'} = $this->_asn1_decode(OCTET_STRING))) {
      return $this->_snmp_decode_error;
   }

   # Decode the PDU type
   if (!defined($this->{'_type'} = $this->_asn1_decode($this->{'_type'}))) {
      return $this->_snmp_decode_error;
   }

   # Return the remaining buffer
   $this->{'_buffer'};
}

sub _snmp_decode_pdu
{
   my $this = shift;

   # Decode the request-id
   if (!defined($this->{'_request_id'} = $this->_asn1_decode(INTEGER))) {
      return $this->_snmp_decode_error;
   }

   # Decode the error-status and error-index 
   if (!defined($this->{'_error_status'} = $this->_asn1_decode(INTEGER))) {
      $this->{'_error_status'} = 0;
      return $this->_snmp_decode_error;
   }
   if (!defined($this->{'_error_index'} = $this->_asn1_decode(INTEGER))) {
      $this->{'_error_index'} = 0;
      return $this->_snmp_decode_error;
   }

   # Return the remaining buffer 
   $this->{'_buffer'};
}

sub _snmp_decode_trap_pdu
{
   my $this = shift;

   # Decode the enterprise 
   if (!defined(
         $this->{'_enterprise'} = $this->_asn1_decode(OBJECT_IDENTIFIER)
      )) 
   {
      return $this->_snmp_decode_error;
   }

   # Decode the agent-addr
   if (!defined($this->{'_agent_addr'} = $this->_asn1_decode(IPADDRESS))) {
      return $this->_snmp_decode_error;
   }

   # Decode the generic-trap type
   if (!defined($this->{'_generic_trap'} = $this->_asn1_decode(INTEGER))) {
      return $this->_snmp_decode_error;
   }

   # Decode the specific-trap type
   if (!defined($this->{'_specific_trap'} = $this->_asn1_decode(INTEGER))) {
      return $this->_snmp_decode_error;
   }

   # Decode the time-stamp
   if (!defined($this->{'_time_stamp'} = $this->_asn1_decode(TIMETICKS))) {
      return $this->_snmp_decode_error;
   }

   # Return the remaining buffer
   $this->{'_buffer'};
}

sub _snmp_decode_var_bind_list
{
   my $this = shift;
   my ($value, $oid, $dup_cnt) = (undef, undef, 0);

   # Decode the VarBindList SEQUENCE
   if (!defined($value = $this->_asn1_decode(SEQUENCE))) {
      return $this->_snmp_decode_error;
   }
   if ($value != $this->_object_buffer_length) {
      return $this->_snmp_decode_error(
         'Encoded VarBindList length not equal to remaining data length' 
      );
   }

   $this->{'_var_bind_list'} = {};

   while ($this->_object_buffer_length) {
      # Decode the VarBind SEQUENCE
      if (!defined($this->_asn1_decode(SEQUENCE))) {
         return $this->_snmp_decode_error;
      }
      # Decode the ObjectName
      if (!defined($oid = $this->_asn1_decode(OBJECT_IDENTIFIER))) {
         return $this->_snmp_decode_error;
      }
      # Decode the ObjectSyntax
      if (!defined($value = $this->_asn1_decode)) {
         return $this->_snmp_decode_error;
      }

      # Create a hash consisting of the OBJECT IDENTIFIER as a
      # key and the ObjectSyntax as the value.  If there is a
      # duplicate OBJECT IDENTIFIER in the VarBindList, we pad 
      # that OBJECT IDENTIFIER with spaces to make a unique
      # key in the hash.
 
      if (exists($this->{'_var_bind_list'}->{$oid})) {
         DEBUG_INFO("duplicate OID, making unique key");
         $oid .= ' ' x ++$dup_cnt; # Pad with spaces 
      } 
      DEBUG_INFO("{ %s => %s }", $oid, $value);
      $this->{'_var_bind_list'}->{$oid} = $value;
   }

   # Return the var_bind_list hash
   $this->{'_var_bind_list'};
}

sub _snmp_send_and_validate
{
   my $this = shift;
   my ($rout, $rin, $value, $buffer) = ('', '', undef, undef);

   # Make sure the socket is still open
   if (!defined($this->{'_socket'})) {
      return $this->_udp_error('Session is closed');
   }

   # Get the number of retries (plus one for the initial send)
   my $retries = $this->{'_retries'} + 1;

   # Setup a vector to indicate received data on the socket
   vec($rin, fileno($this->{'_socket'}), 1) = 1;

   while ((--$retries >= 0) && (defined($this->_udp_send_buffer))) { 

      # Wait until a response is received or the timeout expires
      if (select($rout=$rin, undef, undef, $this->{'_timeout'})) {

         # We need to keep a copy of the original buffer in  
         # case we need to retransmit it.
         $buffer = $this->_object_get_buffer;

         # Reset the var_bind_list and errors that might
         # have been set from a previous message.

         $this->_object_clear_var_bind_list;
         $this->_object_clear_error;

         # Read the data that is available on the socket.  
         if (!defined($this->_udp_recv_buffer)) {
            return $this->_udp_error; 
         }

         # Decode the message SEQUENCE
         if (!defined($value = $this->_asn1_decode(SEQUENCE))) { goto BUFFER; }
         if ($value != $this->_object_buffer_length) {
            $this->_snmp_decode_error(
               'Encoded message length not equal to remaining data length'
            );
            goto BUFFER;
         }

         # Decode and validate the version
         if (!defined($value = $this->_asn1_decode(INTEGER))) { goto BUFFER; }
         if ($value != $this->{'_version'}) {
            $this->_snmp_decode_error(
               "Received version [0x%02x] is not equal to transmitted " .
               "version [0x%02x]", $value, $this->{'_version'}
            );
         }

         # Decode and validate the community
         if (!defined($value = $this->_asn1_decode(OCTET_STRING))) { 
            goto BUFFER;
         }
         if ($value ne $this->{'_community'}) {
            $this->_snmp_decode_error(
               "Received community [%s] is not equal to transmitted " .
               "community [%s]", $value, $this->{'_community'}
            );
         }

         # Decode the PDU type (we are expecting a get-response here)
         if (!defined($this->_asn1_decode(GET_RESPONSE))) { goto BUFFER; }

         # Decode the request-id
         if (!defined($value = $this->_asn1_decode(INTEGER))) { goto BUFFER; }
         if ($value != $this->{'_request_id'}) {
            $this->_snmp_decode_error(
               "Received request-id [%s] is not equal to transmitted " .
               "request-id [%s]", $value, $this->{'_request_id'}
            );
            $this->_object_buffer($buffer);
            redo;
         }
        
         # If there was an error and the request-id matched, return.
         if (defined($this->{'_error'})) { 
            return $this->_snmp_decode_error;
         }

         # Decode and validate the error-status and error-index
         if (!defined($value = $this->_asn1_decode(INTEGER))) {
            return $this->_snmp_decode_error;
         }
         $this->{'_error_status'} = $value;

         if (!defined($value = $this->_asn1_decode(INTEGER))) {
            return $this->_snmp_decode_error;
         }
         $this->{'_error_index'} = $value;

         if (($this->{'_error_status'} != 0) || 
              ($this->{'_error_index'} != 0)) 
         {
            return $this->_snmp_decode_error(
               "Received SNMP %s error-status at error-index %s",
               _snmp_error_status_itoa($this->{'_error_status'}), 
               $this->{'_error_index'}
            );
         }

         # Decode the VarBindList
         return $this->_snmp_decode_var_bind_list;         
      } 
         
      DEBUG_INFO("request timed out, retries = %d", $retries);

      BUFFER:

      # Reset the buffer if it has been used to receive a response already.
      if (defined($buffer)) { 
         $this->_object_buffer($buffer);
         $buffer = undef;
      }
 
   }

   # Exceeded the number of retries
   $this->_udp_error(
      "No response from agent on remote host '%s'", $this->hostname 
   );
}

sub _snmp_compare_get_response
{
   my ($this, $response) = @_;

   if (ref($response) ne ref($this)) {
      $this->_snmp_decode_error('Invalid object reference');
   }

   # Validate the version
   if ($this->{'_version'} != $response->{'_version'}) {
      return $this->_snmp_decode_error(
         "Received version [0x%02x] is not equal to transmitted version " .
         "[0x%02x]", $response->{'_version'}, $this->{'_version'}
      );
   }

   # Validate the community
   if ($this->{'_community'} ne $response->{'_community'}) {
      return $this->_snmp_decode_error(
         "Received community [%s] is not equal to transmitted community [%s]",
         $response->{'_community'}, $this->{'_community'}
      );
   }

   # Validate the request-id
   if ($this->{'_request_id'} != $response->{'_request_id'}) {
      return $this->_snmp_decode_error(
         "Received request-id [%s] is not equal to transmitted request-id [%s]",
         $response->{'_request_id'}, $this->{'_request_id'}
      );
   }

   # Validate the error-status and error-index field.
   if (($response->{'_error_status'} != 0) ||
       ($response->{'_error_index'} != 0))
   {
      # Set the "source" error-status and error-index
      $this->{'_error_status'} = $response->{'_error_status'};
      $this->{'_error_index'}  = $response->{'_error_index'};
      return $this->_snmp_decode_error(
         "Received SNMP %s error-status at error-index %s",
         _snmp_error_status_itoa($response->{'_error_status'}),
         $response->{'_error_index'}
      );
   }

   TRUE;
}

sub _snmp_decode_error
{
   my $this = shift;

   # Clear var_bind_list
   $this->_object_clear_var_bind_list;

   $this->_object_error(@_);
}

###
## Simple Network Management Protocol (SNMP) utilties
###

sub _snmp_error_status_itoa
{
   my $error = shift;

   my @error_status = qw(
      noError
      tooBig
      noSuchName
      badValue
      readOnly
      genError
      noAccess
      wrongType    
      wrongLength
      wrongEncoding
      wrongValue
      noCreation
      inconsistentValue
      resourceUnavailable
      commitFailed
      undoFailed
      authorizationError
      notWritable
      inconsistentName
   ); 

   if (!defined($error)) { return '??'; }
   if (($error > $#error_status) || ($error < 0)) { 
      return sprintf("??(%d)", $error); 
   }

   sprintf("%s(%d)", $error_status[$error], $error);
}


###
## Abstract Syntax Notation One (ASN.1) encode methods
###

my $ASN1_ENCODE_METHODS = {
   INTEGER,            '_asn1_encode_integer',
   OCTET_STRING,       '_asn1_encode_octet_string',
   NULL,               '_asn1_encode_null',
   OBJECT_IDENTIFIER,  '_asn1_encode_object_identifier',
   SEQUENCE,           '_asn1_encode_sequence',
   IPADDRESS,          '_asn1_encode_ipaddress',
   COUNTER,            '_asn1_encode_counter',
   GAUGE,              '_asn1_encode_gauge',
   TIMETICKS,          '_asn1_encode_timeticks',
   OPAQUE,             '_asn1_encode_opaque',
   COUNTER64,          '_asn1_encode_counter64',
   NOSUCHOBJECT,       '_asn1_encode_nosuchobject',
   NOSUCHINSTANCE,     '_asn1_encode_nosuchinstance',
   ENDOFMIBVIEW,       '_asn1_encode_endofmibview',
   GET_REQUEST,        '_asn1_encode_get_request',
   GET_NEXT_REQUEST,   '_asn1_encode_get_next_request',
   GET_RESPONSE,       '_asn1_encode_get_response',
   SET_REQUEST,        '_asn1_encode_set_request',
   TRAP,               '_asn1_encode_trap',
   GET_BULK_REQUEST,   '_asn1_encode_get_bulk_request',
   INFORM_REQUEST,     '_asn1_encode_inform_request',
   SNMPV2_TRAP,        '_asn1_encode_v2_trap'
};

sub _asn1_encode
{
   my ($this, $type, $value) = @_;

   if (!defined($type)) {
      return $this->_asn1_encode_error('ASN.1 type not defined');
   }

   if (exists($ASN1_ENCODE_METHODS->{$type})) {
      my $method = $ASN1_ENCODE_METHODS->{$type};
      $this->$method($value);
   } else {
      $this->_asn1_encode_error("Unknown ASN.1 type [%s]", $type);
   }
}

sub _asn1_encode_type_length
{
   my ($this, $type, $value) = @_;
   my $length = 0;

   if (defined($this->{'_error'})) { return $this->_asn1_encode_error; }

   if (!defined($type)) {
      return $this->_asn1_error('ASN.1 type not defined');
   }

   if (!defined($value)) { $value = ''; }

   $length = length($value);

   if ($length < 0x80) {
      return $this->_object_put_buffer(
         join('', pack('C2', $type, $length), $value)
      );
   } elsif ($length <= 0xff) {
      return $this->_object_put_buffer(
         join('', pack('C3', $type, (0x80 | 1), $length), $value)
      );
   } elsif ($length <= 0xffff) {
      return $this->_object_put_buffer(
         join('', pack('CCn', $type, (0x80 | 2), $length), $value)
      );
   } 
      
   $this->_asn1_encode_error('Unable to encode ASN.1 length');
}

sub _asn1_encode_integer
{
   my ($this, $integer) = @_;

   if (!defined($integer)) {
      return $this->_asn1_encode_error('INTEGER value not defined');
   }

   if ($integer !~ /^-?\d+$/) {
      return $this->_asn1_encode_error('Expected numeric INTEGER value');
   }

   $this->_asn1_encode_integer32(INTEGER, $integer);
}

sub _asn1_encode_unsigned32
{
   my ($this, $type, $u_int32) = @_;

   if (!defined($type)) { $type = INTEGER; }

   if (!defined($u_int32)) { 
      return $this->_asn1_encode_error(
         "%s value not defined", _asn1_itoa($type) 
      );
   }

   if ($u_int32 !~ /^\d+$/) {
      return $this->_asn1_encode_error(
         "Expected positive numeric %s value", _asn1_itoa($type)
      );
   }

   $this->_asn1_encode_integer32($type, $u_int32);
}

sub _asn1_encode_integer32
{
   my ($this, $type, $integer) = @_;
   my ($size, $value, $negative, $prefix) = (4, '', FALSE, FALSE);

   if (!defined($type)) { $type = INTEGER; }

   if (!defined($integer)) {
      return $this->_asn1_encode_error(
         "%s value not defined", _asn1_itoa($type)
      );
   }

   # Determine if the value is positive or negative
   if ($integer =~ /^-/) { $negative = TRUE; } 

   # Check to see if the most significant bit is set, if it is we
   # need to prefix the encoding with a zero byte.

   if (((($integer & 0xff000000) >> 24) & 0x80) && (!$negative)) { 
      $size++; 
      $prefix = TRUE;
   }

   # Remove occurances of nine consecutive ones (if negative) or zeros 
   # from the most significant end of the two's complement integer.

   while ((((!($integer & 0xff800000))) || 
           ((($integer & 0xff800000) == 0xff800000) && ($negative))) && 
           ($size > 1)) 
   {
      $size--;
      $integer <<= 8;
   }

   # Add a zero byte so the integer is decoded as a positive value
   if ($prefix) {
      $value .= pack('x');
      $size--;
   }

   # Build the integer
   while ($size-- > 0) {
      $value .= pack('C', (($integer & 0xff000000) >> 24));
      $integer <<= 8;
   }

   # Encode ASN.1 header
   $this->_asn1_encode_type_length($type, $value);
}

sub _asn1_encode_octet_string
{
   if (!defined($_[1])) {
      return $_[0]->_asn1_encode_error('OCTET STRING value not defined');
   }

   $_[0]->_asn1_encode_type_length(OCTET_STRING, $_[1]);
}

sub _asn1_encode_null 
{ 
   $_[0]->_asn1_encode_type_length(NULL, ''); 
}

sub _asn1_encode_object_identifier
{
   my ($this, $oid) = @_;
   my ($value, $subid, $mask, $bits, $tmask, $tbits) = ('', 0, 0, 0, 0, 0);

   if (!defined($oid)) {
      return $this->_asn1_error('OBJECT IDENTIFIER value not defined');
   }

   # Input is expected in dotted notation, so break it up into subids
   my @subids = split(/\./, $oid);

   # If there was a leading dot on _any_ OBJECT IDENTIFIER passed to 
   # an encode method, return a leading dot on _all_ of the OBJECT
   # IDENTIFIERs in the decode methods.

   if ($subids[0] eq '') { 
      DEBUG_INFO("leading dot present");
      $this->{'_leading_dot'} = TRUE;
      shift(@subids);
   }

   # The first two subidentifiers are encoded into the first identifier
   # using the the equation: subid = ((first * 40) + second).  We just
   # return an error if there are not at least two subidentifiers.

   if (scalar(@subids) < 2) { 
      return $this->_asn1_encode_error('Invalid OBJECT IDENTIFIER length'); 
   }

   $value = 40 * shift(@subids);
   $value = pack('C', ($value + shift(@subids)));

   # Encode each value as seven bits with the most significant bit
   # indicating the end of a subidentifier.

   foreach $subid (@subids) {
      if (($subid < 0x7f) && ($subid >= 0)) {
         $value .= pack('C', $subid);
      } else {
         $mask = 0x7f;
         $bits = 0;
         # Determine the number of bits need to encode the subidentifier
         for ($tmask = 0x7f, $tbits = 0; 
              $tmask != 0x00; 
              $tmask <<= 7, $tbits += 7)
         {
            if ($subid & $tmask) {
               $mask = $tmask;
               $bits = $tbits;
            }
         }
         # Now encode it, using the number of bits from above
         for ( ; $mask != 0x7f; $mask >>= 7, $bits -= 7) {
            # Handle a mask that was truncated above because
            # the subidentifier was four bytes long.
            if ((($mask & 0xffffffff) == 0xffe00000) ||
                 ($mask == 0x1e00000)) 
            {
               $mask = 0xfe00000;
            }
            $value .= pack('C', ((($subid & $mask) >> $bits) | 0x80));
         }
         $value .= pack('C', ($subid & $mask));
      }
   }

   # Encode the ASN.1 header
   $this->_asn1_encode_type_length(OBJECT_IDENTIFIER, $value);
}

sub _asn1_encode_sequence 
{ 
   $_[0]->_asn1_encode_type_length(SEQUENCE, $_[1]); 
}

sub _asn1_encode_ipaddress
{
   my ($this, $address) = @_;

   if (!defined($address)) {
      return $this->_asn1_encode_error('IpAddress not defined');
   }

   if ($address  !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
      return $this->_asn1_encode_error('Expected IpAddress in dotted notation');
   } 

   $this->_asn1_encode_type_length(
      IPADDRESS, pack('C4', split(/\./, $address))
   );
}

sub _asn1_encode_counter 
{ 
   $_[0]->_asn1_encode_unsigned32(COUNTER, $_[1]); 
}

sub _asn1_encode_gauge   
{ 
   $_[0]->_asn1_encode_unsigned32(GAUGE, $_[1]);   
}

sub _asn1_encode_timeticks 
{ 
   $_[0]->_asn1_encode_unsigned32(TIMETICKS, $_[1]); 
}

sub _asn1_encode_opaque
{
   if (!defined($_[1])) {
      return $_[0]->_asn1_encode_error('Opaque value not defined');
   }

   $_[0]->_asn1_encode_type_length(OPAQUE, $_[1]);
}

sub _asn1_encode_counter64
{
   my ($this, $u_int64) = @_;
   my ($quotient, $remainder) = (0, 0);
   my @bytes = ();

   # Validate the SNMP version
   if ($this->version == SNMP_VERSION_1) {
      return $this->_asn1_encode_error(
         'Counter64 not supported in SNMPv1'
      );
   }

   # Validate the passed value
   if (!defined($u_int64)) {
      return $this->_asn1_encode_error('Counter64 value not defined');
   }

   if ($u_int64 !~ /^\+?\d+$/) {
      return $this->_asn1_encode_error(
         'Expected positive numeric Counter64 value'
      );
   }

   # Only load the Math::BigInt module when needed
   use Math::BigInt;

   $u_int64 = Math::BigInt->new($u_int64);

   if ($u_int64 eq 'NaN') {
      return $this->_asn1_encode_error('Invalid Counter64 value');
   }

   # Make sure the value is no more than 8 bytes long
   if ($u_int64->bcmp('18446744073709551615') > 0) {
      return $this->_asn1_encode_error('Counter64 value too high');
   }

   if ($u_int64 == 0) { unshift(@bytes, 0x00); }

   while ($u_int64 > 0) {
      ($quotient, $remainder) = $u_int64->bdiv(256);
      $u_int64 = Math::BigInt->new($quotient);
      unshift(@bytes, $remainder);
   }

   # Make sure that the value is encoded as a positive value
   if ($bytes[0] & 0x80) { unshift(@bytes, 0x00); }

   $this->_asn1_encode_type_length(COUNTER64, pack('C*', @bytes));
}

sub _asn1_encode_nosuchobject
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'noSuchObject not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(NOSUCHOBJECT, '');
}

sub _asn1_encode_nosuchinstance
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'noSuchInstance not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(NOSUCHINSTANCE, '');
}

sub _asn1_encode_endofmibview
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'endOfMibView not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(ENDOFMIBVIEW, '');
}

sub _asn1_encode_get_request
{
   $_[0]->_asn1_encode_type_length(GET_REQUEST, $_[1]);
}

sub _asn1_encode_get_next_request
{
   $_[0]->_asn1_encode_type_length(GET_NEXT_REQUEST, $_[1]);
}

sub _asn1_encode_get_response
{
   $_[0]->_asn1_encode_type_length(GET_RESPONSE, $_[1]);
}

sub _asn1_encode_set_request
{
   $_[0]->_asn1_encode_type_length(SET_REQUEST, $_[1]);
}

sub _asn1_encode_trap
{
   $_[0]->_asn1_encode_type_length(TRAP, $_[1]);
}

sub _asn1_encode_get_bulk_request
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'GetBulkRequest-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(GET_BULK_REQUEST, $_[1]);
}

sub _asn1_encode_inform_request
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'InformRequest-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(INFORM_REQUEST, $_[1]);
}

sub _asn1_encode_v2_trap
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_encode_error(
         'SNMPv2-Trap-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_encode_type_length(SNMPV2_TRAP, $_[1]);
}

sub _asn1_encode_error
{
   my $this = shift;

   # Clear the buffer
   $this->_object_clear_buffer;

   $this->_object_error(@_);
}


###
## Abstract Syntax Notation One (ASN.1) decode methods
###

my $ASN1_DECODE_METHODS = {
   INTEGER,            '_asn1_decode_integer32',
   OCTET_STRING,       '_asn1_decode_octet_string',
   NULL,               '_asn1_decode_null',
   OBJECT_IDENTIFIER,  '_asn1_decode_object_identifier',
   SEQUENCE,           '_asn1_decode_sequence',
   IPADDRESS,          '_asn1_decode_ipaddress',
   COUNTER,            '_asn1_decode_counter',
   GAUGE,              '_asn1_decode_gauge',
   TIMETICKS,          '_asn1_decode_timeticks',
   OPAQUE,             '_asn1_decode_opaque',
   COUNTER64,          '_asn1_decode_counter64',
   NOSUCHOBJECT,       '_asn1_decode_nosuchobject',
   NOSUCHINSTANCE,     '_asn1_decode_nosuchinstance',
   ENDOFMIBVIEW,       '_asn1_decode_endofmibview',
   GET_REQUEST,        '_asn1_decode_get_request',
   GET_NEXT_REQUEST,   '_asn1_decode_get_next_request',
   GET_RESPONSE,       '_asn1_decode_get_response',
   SET_REQUEST,        '_asn1_decode_set_request',
   TRAP,               '_asn1_decode_trap',
   GET_BULK_REQUEST,   '_asn1_decode_get_bulk_request',
   INFORM_REQUEST,     '_asn1_decode_inform_request',
   SNMPV2_TRAP,        '_asn1_decode_v2_trap'
};

sub _asn1_decode
{
   my ($this, $expected) = @_;

   if (defined($this->{'_error'})) { return $this->_asn1_decode_error; }

   my $type = $this->_object_get_buffer(1);

   if (defined($type)) {
      $type = unpack('C', $type);
      if (exists($ASN1_DECODE_METHODS->{$type})) {
         my $method = $ASN1_DECODE_METHODS->{$type};
         if (defined($expected)) {
            if ($type != $expected) {
               return $this->_asn1_decode_error(
                  "Expected %s, but found %s", 
                  _asn1_itoa($expected), _asn1_itoa($type)
               );
            }
         }
         return $this->$method($type);
      } else {
         return $this->_asn1_decode_error("Unknown ASN.1 type [0x%02x]", $type);
      }
   }
 
   $this->_asn1_decode_error;
}

sub _asn1_decode_length
{
   my $this = shift;
   my ($length, $byte_cnt) = (0, 0);
  
   if (defined($this->{'_error'})) { return $this->_asn1_decode_error; }

   if (!defined($length = $this->_object_get_buffer(1))) {
      return $this->_asn1_decode_error;
   } 
   $length = unpack('C', $length);
 
   if ($length & 0x80) {
      $byte_cnt = ($length & 0x7f);
      if ($byte_cnt == 0) {
         return $this->_asn1_decode_error(
            'Indefinite ASN.1 lengths not supported'
         );  
      } elsif ($byte_cnt <= 4) {
         if (!defined($length = $this->_object_get_buffer($byte_cnt))) {
            return $this->_asn1_decode_error;
         }
         $length = unpack('N', ("\0" x (4 - $byte_cnt) . $length)); 
      } else {   
         return $this->_asn1_decode_error(
            "ASN.1 length too long (%d bytes)", $byte_cnt 
         );
      }
   }
 
   $length;
}

sub _asn1_decode_integer32
{
   my ($this, $type) = @_;
   my ($length, $integer, $negative, $byte) = (undef, 0, FALSE, undef);

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   # Return an error if the object length is zero
   if ($length < 1) {
      return $this->_asn1_decode_error(
         "%s length equal to zero", _asn1_itoa($type)
      );
   } 
      
   if (!defined($byte = $this->_object_get_buffer(1))) { 
      return $this->_asn1_decode_error; 
   }
   $length--;

   # If the first bit is set, the integer is negative
   if (($byte = unpack('C', $byte)) & 0x80) {
      if (($type == INTEGER) || 
          (!($this->{'_translate'} & TRANSLATE_UNSIGNED)))
      {
         $integer = -1;
         $negative = TRUE; 
      } else {
         DEBUG_INFO("translating sign bit for %s", _asn1_itoa($type));
      } 
   }

   if (($length > 4) || (($length > 3) && ($byte != 0x00))) {
      return $this->_asn1_decode_error(
         "%s length too long (%d bytes)", _asn1_itoa($type), ($length + 1)
      );
   }

   $integer = (($integer << 8) | $byte);

   while ($length--) {
      if (!defined($byte = $this->_object_get_buffer(1))) {
         return $this->_asn1_decode_error;
      }
      $integer = (($integer << 8) | unpack('C', $byte));
   }
 
   if ($negative) { 
      sprintf("%d", $integer); 
   } else {
      sprintf("%u", $integer);
   }
}

sub _asn1_decode_octet_string
{
   my ($this, $type) = @_;
   my ($length, $string) = (undef, undef);

   if (!defined($type)) { $type = OCTET_STRING; }

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   my $mask = ($type == OPAQUE) ? TRANSLATE_OPAQUE : TRANSLATE_OCTET_STRING;

   if (defined($string = $this->_object_get_buffer($length))) {
      if (($string =~ /[\x01-\x08\x0b\x0e-\x1f\x7f-\xff]/g) && 
          ($this->{'_translate'} & $mask)) 
      {
         DEBUG_INFO(
            "translating %s to printable hex string", _asn1_itoa($type)
         );
         return sprintf("0x%s", unpack('H*', $string));
      } else {
         return $string;
      }
   } else {
      return $this->_asn1_decode_error;
   }
}

sub _asn1_decode_null
{
   my $this = shift;
   my ($length) = (undef);

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length != 0) {
      return $this->_asn1_decode_error('NULL length not equal to zero');
   }

   if ($this->{'_translate'} & TRANSLATE_NULL) {
      DEBUG_INFO("translating NULL to 'NULL' string");
      'NULL';
   } else {
      '';
   }
}

sub _asn1_decode_object_identifier
{
   my $this = shift;
   my ($length, $subid_cnt, $subid, $byte) = (undef, 1, 0, undef);
   my (@oid);

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length < 1) { 
      return $this->_asn1_decode_error(
         'OBJECT IDENTIFIER length equal to zero'
      );
   }

   while ($length > 0) {
      $subid = 0;
      do {
         if (!defined($byte = $this->_object_get_buffer(1))) {
            return $this->_asn1_decode_error;
         }   
         $byte = unpack('C', $byte);
         if ($subid >= 0xffffffff) {
            return $this->_asn1_decode_error(
               'OBJECT IDENTIFIER subidentifier too large'
            );
         }
         $subid = (($subid << 7) + ($byte & 0x7f)); 
         $length--;
      } while ($byte & 0x80);
      $oid[$subid_cnt++] = $subid;
   }

   # The first two subidentifiers are encoded into the first identifier
   # using the the equation: subid = ((first * 40) + second).

   $subid  = $oid[1];
   $oid[1] = int($subid % 40);
   $oid[0] = int(($subid - $oid[1]) / 40);

   # Return the OID in dotted notation (optionally with a leading dot
   # if one was passed to the encode routine).

   if ($this->{'_leading_dot'}) {
      DEBUG_INFO("adding leading dot");
      '.' . join('.', @oid);
   } else {
      join('.', @oid);
   }
}

sub _asn1_decode_sequence
{
   # Return the length, instead of the value
   $_[0]->_asn1_decode_length;
}

sub _asn1_decode_ipaddress
{
   my $this = shift;
   my ($length, $address) = (undef, undef);

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length != 4) {
      return $this->_asn1_decode_error(
         "Invalid IpAddress length (% byte%s)", 
         $length, ($length == 1 ? '' : 's')
      );
   }

   if (defined($address = $this->_object_get_buffer(4))) {
      join('.', unpack('C4', $address));
   } else {
      $this->_asn1_decode_error;
   }
}

sub _asn1_decode_counter 
{
   $_[0]->_asn1_decode_integer32(COUNTER);
}

sub _asn1_decode_gauge   
{ 
   $_[0]->_asn1_decode_integer32(GAUGE);
}

sub _asn1_decode_timeticks
{
   my $this = shift;
   my $ticks = undef;

   if (defined($ticks = $this->_asn1_decode_integer32(TIMETICKS))) {
      if ($this->{'_translate'} & TRANSLATE_TIMETICKS) {
         DEBUG_INFO("translating %u TimeTicks to time\n", $ticks);
         return _asn1_ticks_to_time($ticks);
      } else {
         return $ticks;
      }
   } else {
      return $this->_asn1_decode_error;
   }
}

sub _asn1_decode_opaque 
{ 
   $_[0]->_asn1_decode_octet_string(OPAQUE); 
}

sub _asn1_decode_counter64
{
   my $this = shift;
   my ($length, $byte, $negative) = (undef, undef, FALSE);

   # Verify the SNMP version
   if ($this->version == SNMP_VERSION_1) {
      return $this->_asn1_decode_error(
         'Counter64 not supported in SNMPv1'
      );
   }

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length < 1) {
      return $this->_asn1_decode_error('Counter64 length equal to zero');
   }

   if (!defined($byte = $this->_object_get_buffer(1))) {
      return $this->_asn1_decode_error;
   }
   $length--;
   $byte = unpack('C', $byte);

   if (($length > 8) || (($length > 7) && ($byte != 0x00))) {
      return $this->_asn1_decode_error(
         "Counter64 length too long (%d bytes)", ($length + 1)
      );
   }

   # Only load the Math::BigInt module when needed
   use Math::BigInt;

   if ($byte & 0x80) { 
      if (!($this->{'_translate'} & TRANSLATE_UNSIGNED)) { 
         $negative = TRUE;
         $byte = $byte ^ 0xff; 
      } else {
         DEBUG_INFO('translating sign bit for Counter64'); 
      }
   }

   my $u_int64 = Math::BigInt->new($byte);

   while ($length-- > 0) {
      if (!defined($byte = $this->_object_get_buffer(1))) {
         return $this->_asn1_decode_error;
      }
      $byte = unpack('C', $byte);
      if ($negative) { $byte = $byte ^ 0xff; }
      $u_int64 = $u_int64->bmul(256);
      $u_int64 = Math::BigInt->new($u_int64);
      $u_int64 = $u_int64->badd($byte);
      $u_int64 = Math::BigInt->new($u_int64);
   };

   # If the value is negative the other end incorrectly encoded  
   # the Counter64 since it should always be a positive value. 

   if ($negative) {
      $byte = Math::BigInt->new('-1');
      $u_int64 = $byte->bsub($u_int64);
   }

   # Hack for Perl 5.6.0 (force to string or substitution does not work).
   if ($] ge '5.005') { $u_int64 .= ''; }

   # Remove the plus sign (or should we leave it to imply Math::BigInt?)
   $u_int64 =~ s/^\+//;

   $u_int64;
}

sub _asn1_decode_nosuchobject
{
   my $this = shift;
   my ($length) = (undef);

   if ($this->version == SNMP_VERSION_1) {
      return $this->_asn1_decode_error(
         'noSuchObject not supported in SNMPv1'
      );
   }
 
   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length != 0) {
      return $this->_asn1_decode_error('noSuchObject length not equal to zero');
   }

   if ($this->{'_translate'} & TRANSLATE_NOSUCHOBJECT) {
      DEBUG_INFO("translating noSuchObject to 'noSuchObject' string");
      'noSuchObject';
   } else {
      $this->{'_error_status'} = NOSUCHOBJECT;
      '';
   }
}

sub _asn1_decode_nosuchinstance
{
   my $this = shift;
   my ($length) = (undef);

   if ($this->version == SNMP_VERSION_1) {
      return $this->_asn1_decode_error(
         'noSuchInstance not supported in SNMPv1'
      );
   }

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length != 0) {
      return $this->_asn1_decode_error(
         'noSuchInstance length not equal to zero'
      );
   }

   if ($this->{'_translate'} & TRANSLATE_NOSUCHINSTANCE) {
      DEBUG_INFO("translating noSuchInstance to 'noSuchInstance' string");
      'noSuchInstance';
   } else {
      $this->{'_error_status'} = NOSUCHINSTANCE;
      '';
   }
}

sub _asn1_decode_endofmibview
{
   my $this = shift;
   my ($length) = (undef);

   if ($this->version == SNMP_VERSION_1) {
      return $this->_asn1_decode_error(
         'endOfMibView not supported in SNMPv1'
      );
   }

   if (!defined($length = $this->_asn1_decode_length)) {
      return $this->_asn1_decode_error;
   }

   if ($length != 0) {
      return $this->_asn1_decode_error('endOfMibView length not equal to zero');
   }

   if ($this->{'_translate'} & TRANSLATE_ENDOFMIBVIEW) {
      DEBUG_INFO("translating endOfMibView to 'endOfMibView' string");
      'endOfMibView';
   } else {
      $this->{'_error_status'} = ENDOFMIBVIEW;
      '';
   }
}

sub _asn1_decode_pdu
{
   # Generic methods used to decode the PDU type.  The ASN.1 type is
   # returned by the method as passed by the generic decode routine.

   if ((defined($_[0]->_asn1_decode_length)) && (defined($_[1]))) {
      $_[1];
   } else {
      $_[0]->_asn1_decode_error('ASN.1 PDU type not defined');
   } 
}

sub _asn1_decode_get_request      
{ 
   $_[0]->_asn1_decode_pdu(GET_REQUEST); 
}

sub _asn1_decode_get_next_request 
{ 
   $_[0]->_asn1_decode_pdu(GET_NEXT_REQUEST); 
}

sub _asn1_decode_get_response      
{ 
   $_[0]->_asn1_decode_pdu(GET_RESPONSE); 
}

sub _asn1_decode_set_request      
{ 
   $_[0]->_asn1_decode_pdu(SET_REQUEST); 
}

sub _asn1_decode_trap             
{ 
   $_[0]->_asn1_decode_pdu(TRAP); 
}

sub _asn1_decode_get_bulk_request 
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_decode_error(
         'GetBulkRequest-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_decode_pdu(GET_BULK_REQUEST); 
}

sub _asn1_decode_inform_request
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_decode_error(
         'InformRequest-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_decode_pdu(INFORM_REQUEST);
}

sub _asn1_decode_v2_trap
{
   if ($_[0]->version == SNMP_VERSION_1) {
      return $_[0]->_asn1_decode_error(
         'SNMPv2-Trap-PDU not supported in SNMPv1'
      );
   }

   $_[0]->_asn1_decode_pdu(SNMPV2_TRAP);
}

sub _asn1_decode_error
{
   my $this = shift;

   $this->_object_error(@_);
}


###
## Abstract Syntax Notation One (ASN.1) utility functions 
###

sub _asn1_itoa 
{
   my $type = shift;

   my $types = {
      INTEGER,            'INTEGER', 
      OCTET_STRING,       'OCTET STRING', 
      NULL,               'NULL', 
      OBJECT_IDENTIFIER,  'OBJECT IDENTIFER', 
      SEQUENCE,           'SEQUENCE', 
      IPADDRESS,          'IpAddress', 
      COUNTER,            'Counter', 
      GAUGE,              'Gauge', 
      TIMETICKS,          'TimeTicks', 
      OPAQUE,             'Opaque', 
      COUNTER64,          'Counter64',
      NOSUCHOBJECT,       'noSuchObject',
      NOSUCHINSTANCE,     'noSuchInstance',
      ENDOFMIBVIEW,       'endOfMibView',
      GET_REQUEST,        'GetRequest-PDU', 
      GET_NEXT_REQUEST,   'GetNextRequest-PDU', 
      GET_RESPONSE,       'GetResponse-PDU', 
      SET_REQUEST,        'SetRequest-PDU', 
      TRAP,               'Trap-PDU',
      GET_BULK_REQUEST,   'GetBulkRequest-PDU',
      INFORM_REQUEST,     'InformRequest-PDU',
      SNMPV2_TRAP,        'SNMPv2-Trap-PDU' 
   };

   if (!defined($type)) { return '??'; }

   if (exists($types->{$type})) {
      $types->{$type};
   } else {
      sprintf("?? [0x%02x]", $type);
   }
}

sub _asn1_oid_context_match
{
   my ($oid_p, $oid_c) = @_;
   my ($parent, $child) = (undef, undef);

   # Compares the parent OID (oid_p) to the child OID (oid_c)
   # and returns true if the child is equal to or is a subtree 
   # of the parent OID.
    
   if (!defined($oid_p)) { return FALSE; }
   if (!defined($oid_c)) { return FALSE; }

   # Remove leading dots
   $oid_p =~ s/^\.//;
   $oid_c =~ s/^\.//;

   my @subid_p = split(/\./, $oid_p);
   my @subid_c = split(/\./, $oid_c);

   while (@subid_p) {
      if (!defined($parent = shift(@subid_p))) { return TRUE; }
      if (!defined($child  = shift(@subid_c))) { return FALSE; }
      if ($parent != $child) { return FALSE; }
   }

   TRUE;
}

sub _asn1_oid_lex_sort 
{ 
   sort _asn1_lexicographical @_; 
}

sub _asn1_lexicographical
{
   my ($aa, $bb);

   my @a = split(/\./, $a);
   if ($a[0] eq '') { shift(@a); }

   my @b = split(/\./, $b);  
   if ($b[0] eq '') { shift(@b); } 

   while (@a) {
      if (!defined($aa = shift(@a))) { return -1; }
      if (!defined($bb = shift(@b))) { return 1;  }
      if ($aa < $bb) { return -1; } 
      if ($aa > $bb) { return 1;  }
   }

   scalar(@b) ? -1 : 0;
}

sub _asn1_ticks_to_time 
{
   my $ticks = shift;

   if (!defined($ticks)) { $ticks = 0; }

   my $days = int($ticks / (24 * 60 * 60 * 100));
   $ticks %= (24 * 60 * 60 * 100);

   my $hours = int($ticks / (60 * 60 * 100));
   $ticks %= (60 * 60 * 100);

   my $minutes = int($ticks / (60 * 100));
   $ticks %= (60 * 100);

   my $seconds = ($ticks / 100);

   if ($days != 0){
      sprintf("%d day%s, %02d:%02d:%05.02f", $days,
         ($days == 1 ? '' : 's'), $hours, $minutes, $seconds);
   } elsif ($hours != 0) {
      sprintf("%d hour%s, %02d:%05.02f", $hours,
         ($hours == 1 ? '' : 's'), $minutes, $seconds);
   } elsif ($minutes != 0) {
      sprintf("%d minute%s, %05.02f", $minutes, 
         ($minutes == 1 ? '' : 's'), $seconds);
   } else {
      sprintf("%04.02f second%s", $seconds, ($seconds == 1 ? '' : 's'));
   }

}


###
## User Datagram Protocol (UDP) methods
###

sub _udp_send_message
{
   my $this = shift;
   my ($retries, $rout, $rin, $late) = (0, '', '', 0);

   # Make sure the socket is still open
   if (!defined($this->{'_socket'})) {
      return $this->_udp_error('Session is closed');
   }

   # Get the number of retries
   $retries = $this->{'_retries'};

   # Setup a vector to indicate received data on the socket
   vec($rin, fileno($this->{'_socket'}), 1) = 1;

   do {
      if (!defined($this->_udp_send_buffer)) { return $this->_udp_error; }
      if (select($rout=$rin, undef, undef, $this->{'_timeout'})) {
         return $this->_udp_recv_buffer;
      } else {
         DEBUG_INFO("request timed out, retries = %d", $retries);
         $retries--;
      }
   } while ($retries >= 0);

   # Exceeded the number of retries
   $this->_udp_error(
      "No response from agent on remote host '%s'", $this->hostname 
   );
}

sub _udp_send_buffer
{
   my $this = shift;
   my ($length, $host_port, $host_addr) = (0, undef, undef);

   # Make sure the socket is still open
   if (!defined($this->{'_socket'})) {
      return $this->_udp_error('Session is closed');
   }

   ($host_port, $host_addr) = sockaddr_in($this->{'_sockaddr'});
   DEBUG_INFO("address %s, port %d", inet_ntoa($host_addr), $host_port); 
   $this->_debug_dump_buffer;

   # Transmit the contents of the buffer
   if (!defined($length = 
         send($this->{'_socket'}, $this->{'_buffer'}, 0, $this->{'_sockaddr'})
      ))
   {
      return $this->_udp_error("send(): %s", $!);
   }

   # Return the number of bytes transmitted
   $length;
}

sub _udp_recv_buffer
{
   my $this = shift;
   my $sockaddr = undef;

   # Make sure the socket is still open
   if (!defined($this->{'_socket'})) {
      return $this->_udp_error('Session is closed');
   }

   # Clear the contents of the buffer
   $this->_object_clear_buffer;

   # Fill the buffer
   if (!defined($sockaddr = 
         recv($this->{'_socket'}, $this->{'_buffer'}, $this->{'_mtu'} + 1, 0)
      ))
   {
      return $this->_udp_error("recv(): %s", $!);
   }

   # Check the Maximum Transport Unit 
   if ($this->_object_buffer_length > $this->{'_mtu'}) {
      return $this->_udp_error('Received PDU size exceeded MTU');
   }

   my ($host_port, $host_addr) = sockaddr_in($sockaddr);
   DEBUG_INFO("address %s, port %d", inet_ntoa($host_addr), $host_port);
   $this->_debug_dump_buffer;

   # Return the address structure
   $sockaddr;
}

sub _udp_error
{
   my $this = shift;

   $this->_object_error(@_);
}


###
## Semi-private accessor methods
###


sub _fsm_request_id
{
   # We keep a copy of the request-id since it can change in a callback
   # when another message is queued.  This is mainly done for debugging
   # purposes.

   (@_ == 2) ? $_[0]->{'_fsm_request_id'} = $_[1] : $_[0]->{'_fsm_request_id'};
}

sub _request_id
{
   $_[0]->{'_request_id'};
}

sub _socket
{
   (@_ == 2) ? $_[0]->{'_socket'} = $_[1] : $_[0]->{'_socket'};
}

sub _type
{
   (@_ == 2) ? $_[0]->{'_type'} = $_[1] : $_[0]->{'_type'};
}

sub _retries_left_now
{
   # Decrements the number of retries and returns true if the
   # the count is greater than 0.

   $_[0]->{'_retries'}-- > 0;
}


###
## Object specific methods
###

sub _object_event_delay
{
   if (@_ == 2) {
      if ($_[1] !~ /^\d+(\.\d+)?$/) {
         return $_[0]->_object_error("Invalid delay value [%s]", $_[1]);
      }
      $_[0]->{'_event_delay'} = $_[1];
   }

   exists($_[0]->{'_event_delay'}) ? $_[0]->{'_event_delay'} : 0;
}

sub _object_queue_message
{
   my $this = shift;

   if ((!$this->{'_nonblocking'}) || (!defined($this->{'_fsm'}))) {
      return $this->_object_encode_error(
         'Unable to queue message for a blocking session'
      );
   }

   if (!defined($this->{'_socket'})) {
      return $this->_object_encode_error('Session is closed');
   }

   if (!defined($this->{'_fsm'}->queue_message($this))) {
      $this->_object_encode_error('Failed to queue message');
   }

   TRUE;
}

sub _object_add_callback
{
   my ($this, $callback) = @_;

   # Callbacks can be passed in two different ways.  If the callback
   # has options, the callback must be passed as an ARRAY reference
   # with the first element being a CODE reference and the remaining
   # elements the arguments.  If the callback has not options it
   # is just passed as a CODE reference.

   if ((ref($callback) eq 'ARRAY') && (ref($callback->[0]) eq 'CODE')) {
      $this->{'_callback'} = $callback;
   } elsif (ref($callback) eq 'CODE') {
      $this->{'_callback'} = [$callback];
   } elsif (!defined($callback)) {
      $this->{'_callback'} = undef;  # Used to clear the callback
   } else {
      return $this->_object_error('Invalid callback format');
   }

   TRUE;
}

sub _object_invoke_callback
{
   my $this = shift;

   # Callbacks are invoked with a reference to the copy of the original
   # object followed by the users parameters.

   if (defined($this->{'_callback'})) {
      my @argv = @{$this->{'_callback'}};
      my $callback = shift(@argv);
      if (ref($callback) ne 'CODE') { return($this->{'_callback'} = undef); }
      unshift(@argv, $this);
      eval { &{$callback}(@argv) };
      if ($@ ne '') { DEBUG_INFO("eval error: %s", $@); }
      return $@;
   }
   DEBUG_INFO("callback not defined");

   $this->{'_callback'};
}

sub _object_copy
{
   my $this = shift;

   my $copy = bless {}, ref($this);

   foreach (keys(%{$this})) { $copy->{$_} = $this->{$_}; }

   $copy;
}

sub _object_get_table_cb
{
   my ($this, $argv) = @_;

   # Use get-next-requests or get-bulk-requests until the response is
   # not a subtree of the base OBJECT IDENTIFIER.  Return the table only
   # if there are no errors other than a noSuchName(2) error since the
   # table could be at the end of the tree.  Also return the table when
   # the value of the OID equals endOfMibView(2) when using SNMPv2c.

   # Assign the "real" callback to the object
   $this->{'_callback'} = $argv->{'callback'};

   # Check to see if the var_bind_list is defined (was there an error?)

   if (defined(my $result = $this->var_bind_list)) {

      my @oids = oid_lex_sort(keys(%{$result}));
      my ($next_oid, $end_of_table) = (undef, FALSE);

      do {

         $next_oid = shift(@oids);
 
         # Add the entry to the table

         if (_asn1_oid_context_match($argv->{'base_oid'}, $next_oid)) {

            if (!exists($argv->{'table'}->{$next_oid})) {
               $argv->{'table'}->{$next_oid} = $result->{$next_oid};
            } elsif (($result->{$next_oid} eq 'endOfMibView')      # translate
                     || (($result->{$next_oid} eq '')              # !translate
                        && ($this->error_status == ENDOFMIBVIEW)))
            {
               $this->_object_clear_error;
               $end_of_table = TRUE;
            } else {
               $argv->{'repeat_cnt'}++;
            }

            # Check to make sure that the remote host does not respond
            # incorrectly causing the get-next-requests to loop forever.

            if ($argv->{'repeat_cnt'} > 5) {
               $this->_object_decode_error(
                  'Loop detected with table on remote host'
               );
               return $this->_object_invoke_callback;
            }

         } else {
            $end_of_table = TRUE;
         }
      
      } while (@oids); 

      # Queue the next request if we are not at the end of the table.

      if (!$end_of_table) {

         if ($this->version == SNMP_VERSION_1) {
            $result = $this->get_next_request(
               -callback    => [\&_object_get_table_cb, $argv],
               -delay       => 0,
               -varbindlist => [$next_oid]
            );
         } else {
            $result = $this->get_bulk_request(
               -callback       => [\&_object_get_table_cb, $argv],
               -delay          => 0,
               -maxrepetitions => GET_TABLE_MAX_REPETITIONS,
               -varbindlist    => [$next_oid]
            );
         }

         if (!defined($result)) {
            return $this->_object_invoke_callback;
         } else {
            return $result;
         }

      }

      # Copy the table to the var_bind_list
      $this->{'_var_bind_list'} = $argv->{'table'}; 

   } 

   # Check for noSuchName(2) error
   if ($this->error_status == 2) {
      $this->_object_clear_error;
      $this->{'_var_bind_list'} = $argv->{'table'};
   }
   
   if (!defined($argv->{'table'})) {
      $this->_object_decode_error(
         'Requested table is empty or does not exist'
      );
   }

   # Invoke the user defined callback. 
   $this->_object_invoke_callback;
}

sub _object_put_buffer
{
   my ($this, $prefix) = @_;

   # Do not do anything if there has already been an error
   if (defined($this->{'_error'})) { return $this->_object_encode_error; }

   # Make sure we do not exceed our MTU
   if (($this->_object_buffer_length + length($prefix)) > $this->{'_mtu'}) {
      return $this->_object_encode_error('PDU size exceeded MTU');
   }
 
   # Add the prefix to the current buffer
   if ((defined($prefix)) && ($prefix ne '')) {
      $this->{'_buffer'} = join('', $prefix, $this->{'_buffer'});
   } 

   # Return what was just added in case someone wants it
   $prefix;
}

sub _object_get_buffer
{
   my ($this, $offset) = @_;
   my $substr = '';

   # Do not do anything if there has already been an error
   if (defined($this->{'_error'})) { return $this->_object_decode_error; }
  
   # Either return the whole buffer or a sub-string from the 
   # beginning of the buffer and then set the buffer equal to
   # what is left in the buffer
 
   if (defined($offset)) {
      $offset = abs($offset);
      if ($offset > length($this->{'_buffer'})) {
         return $this->_object_decode_error('Unexpected end of buffer');
      } else {
         $substr = substr($this->{'_buffer'}, 0, $offset);
         $this->{'_buffer'} = substr($this->{'_buffer'}, $offset);
      }
   } else {
      $substr = $this->{'_buffer'};
      $this->{'_buffer'} = ''; 
   }

   $substr;
}

sub _object_clear_buffer 
{ 
   $_[0]->{'_buffer'} = ''; 
}

sub _object_buffer
{
   (@_ == 2) ? $_[0]->{'_buffer'} = $_[1] : $_[0]->{'_buffer'};
}

sub _object_clear_var_bind_list 
{ 
   $_[0]->{'_var_bind_list'} = undef; 
}

sub _object_clear_error
{
   $_[0]->{'_error_status'} = 0;
   $_[0]->{'_error_index'}  = 0;
   $_[0]->{'_error'} = undef;
}

sub _object_clear_snmp_message
{
   my @fields = qw(
      _version _community _type _request_id _error_status _error_index
      _enterprise _agent_addr _generic_trap _specific_trap _time_stamp
   );

   foreach (@fields) { if (exists($_[0]->{$_})) { $_[0]->{$_} = undef; } }
}

sub _object_clear_leading_dot 
{ 
   $_[0]->{'_leading_dot'} = FALSE; 
}

sub _object_buffer_length 
{ 
   length $_[0]->{'_buffer'}; 
}

sub _object_translate_mask
{
   # Define the translate bitmask for the object based on the
   # passed truth value and mask.

   if (@_ != 3) {
      return $_[0]->{'_translate'};
   }

   if ($_[1]) {
      $_[0]->{'_translate'} |= $_[2];  # Enable 
   } else {
      $_[0]->{'_translate'} &= ~$_[2]; # Disable 
   }
}

sub _object_encode_error
{
   my $this = shift;

   # Clear the buffer
   $this->_object_clear_buffer;

   $this->_object_error(@_);
}

sub _object_decode_error
{
   my $this = shift;

   # Clear the var_bind_list
   $this->_object_clear_var_bind_list;

   $this->_object_error(@_);
}

sub _object_error
{
   my ($this, $format, @message) = @_;

   if (!defined($this->{'_error'})) {
      $this->{'_error'} = sprintf $format, @message;
      if ($this->debug) {
         my $index = (caller(1))[3] =~ /error/ ? 1 : 0;
#         my $index = caller(3) ? 1 : 0; 
         printf("error: [%d] %s(): %s\n", 
            (caller($index))[2], (caller($index + 1))[3], $this->{'_error'} 
         );
      }
   }

   undef;
}


###
## Debug functions/methods
###

sub DEBUG_INFO
{
   if (!$Net::SNMP::DEBUG) { return $Net::SNMP::DEBUG; }

   my $format = sprintf("debug: [%d] %s(): ", (caller(0))[2], (caller(1))[3]);
   $format = join('', $format, shift(@_), "\n");
   printf $format, @_;

   $Net::SNMP::DEBUG;
}

sub _debug_dump_buffer
{
   my $this = shift;
   my ($length, $offset, $line, $hex) = (0, 0, '', '');

   if (!$this->debug) { return undef; }

   $length = length($this->{'_buffer'});

   DEBUG_INFO("%d byte%s", $length, ($length == 1 ? '' : 's'));
  
   while ($length > 0) {
      if ($length >= 16) { 
         $line = substr($this->{'_buffer'}, $offset, 16);
      } else {
         $line = substr($this->{'_buffer'}, $offset, $length);
      }
      $hex  = unpack('H*', $line);
      $hex .= ' ' x (32 - length($hex));
      $hex  = sprintf("%s %s %s %s  " x 4, unpack('a2' x 16, $hex));
      $line =~ s/[\x00-\x1f\x7f-\xff]/./g;
      printf("[%03d]  %s %s\n", $offset, uc($hex), $line);
      $offset += 16;
      $length -= 16;
   }
   print("\n");
   
   $this->{'_buffer'};
}

# ============================================================================
1; # [end Net::SNMP] 
# ============================================================================

package Net::SNMP::FSM;

# $Id: SNMP_365.pm,v 1.1.1.1 2003/06/11 19:33:42 sartori Exp $
# $Source: /usr/local/cvsroot/ifgraph-0.4.10/lib/Net/SNMP_365.pm,v $

# Finite State Machine for the Net::SNMP event loop.

# Copyright (c) 1999-2001 David M. Town <david.town@marconi.com>.
# All rights reserved.

# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself.

# ============================================================================

## Version of Net::SNMP::FSM module

$Net::SNMP::FSM::VERSION = 2.11;

## Import and initialize global symbols

sub BEGIN
{
   *DEBUG_INFO   = \&Net::SNMP::DEBUG_INFO;
   *FALSE        = \&Net::SNMP::FALSE;
   *GET_RESPONSE = \&Net::SNMP::GET_RESPONSE;
   *MINIMUM_MTU  = \&Net::SNMP::MINIMUM_MTU;
   *SNMPV2_TRAP  = \&Net::SNMP::SNMPV2_TRAP;
   *TRAP         = \&Net::SNMP::TRAP;
   *TRUE         = \&Net::SNMP::TRUE;

   # Use a higher resolution of time() if the
   # Time::HiRes module is available.

   if (eval('require Time::HiRes')) {
      Time::HiRes->import('time');
   }
}

## Finite State Machine state definitions

sub STATE_INIT()         { 0 }
sub STATE_PENDING()      { 1 }
sub STATE_WAITING()      { 2 }

# [public methods] -----------------------------------------------------------

sub new
{
   my ($class, %argv) = @_;

   my $this = bless {
      '_active'        => FALSE,  # State of this FSM object
      '_blocking'      => TRUE,   # Block on select()
      '_decode_object' => undef,  # Net::SNMP object used to decode responses
      '_event_queue_h' => undef,  # Head of the event queue
      '_event_queue_t' => undef,  # Tail of the event queue 
      '_request_ids'   => {},     # Cache of outstanding request-ids
      '_rin'           => '',     # Socket vector
      '_sockets'       => {},     # List of sockets to monitor
   }, $class;

   # Create a Net::SNMP object to use to decode the responses.

   $this->{'_decode_object'} = Net::SNMP->new(-mtu => MINIMUM_MTU);

   if (!defined($this->{'_decode_object'})) {
      return $this->_object_error('Failed to create Net::SNMP object');
   }

   $this;
}

sub queue_message 
{ 
   $_[0]->_action_queue($_[1]); 
}

sub event_loop 
{ 
   $_[0]->{'_active'}   = TRUE;
   $_[0]->{'_blocking'} = TRUE;
   $_[0]->_event_loop; 
   $_[0]->_object_clear;
}

sub one_event 
{ 
   $_[0]->{'_active'}   = TRUE;
   $_[0]->{'_blocking'} = FALSE;
   if (defined($_[0]->{'_event_queue_h'})) { $_[0]->_event_handle; } 
   $_[0]->{'_active'}   = FALSE;
}


# [private methods] ----------------------------------------------------------

sub _event_loop
{
   while (defined($_[0]->{'_event_queue_h'})) { $_[0]->_event_handle; }
}

sub _event_handle
{
   my ($this) = @_;

   # Events are sorted by time, so the event at the head of the list
   # is the next event that needs to be executed.

   my $event = $this->{'_event_queue_h'}; 

   # Calculate a timeout based on the current time and the lowest 
   # event time (if the event does not need initialized).
   
   my $timeout = 0;
   if ($event->state != STATE_INIT) {
      $timeout = $event->time - time();
   }

   # If the timeout is less than 0, we are running late.
   if ($timeout >= 0) {
      DEBUG_INFO("poll delay = %f" , $timeout);
      if (select(my $rout = $this->{'_rin'}, undef, undef, 
                 ($this->{'_blocking'} ? $timeout : 0))) 
      {
         # Find out which socket has data ready
         foreach (keys(%{$this->{'_sockets'}})) {
            if (defined($rout) && vec($rout, $_, 1)) {
               DEBUG_INFO("socket handle [%d] ready", $_);
               return $this->_action_read_data($this->{'_sockets'}->{$_});
            }
         }
      } elsif ((!$this->{'_blocking'}) && ($timeout > 0)) {
         return $event;
      }
   } else {
      DEBUG_INFO("skew = %f", -$timeout);
   }
  
   # If we made it here, no data was received during the poll cycle, so 
   # we take action on the object at the head of the queue.

   if ($event->state == STATE_INIT) {
      return $this->_action_init($event); 
   } elsif ($event->state == STATE_PENDING) {
      return $this->_action_send($event);
   } elsif ($event->state == STATE_WAITING) {
      return $this->_action_timeout($event);
   }

   # Once we reach here, we are done with the object, so remove it
   # from the head of the queue.
     
   $this->_object_delete_event($event);
}


###
## FSM Actions
###

sub _action_init
{

   DEBUG_INFO("initializing request-id = %s (%s)",
      $_[1]->object->_fsm_request_id, $_[1]->object->hostname
   );

   if ($_[1]->time == 0) { # No delay, send immediately
      $_[0]->_action_send($_[1]);
   } else {
      $_[0]->_object_schedule_event($_[1], STATE_PENDING, $_[1]->time);
   }
}

sub _action_send
{
   DEBUG_INFO("sending request-id = %s (%s)",
      $_[1]->object->_fsm_request_id, $_[1]->object->hostname
   );

   # Send the message
   if (!defined($_[1]->object->_udp_send_buffer)) {
      DEBUG_INFO("%s", $_[1]->object->error);
      $_[0]->_object_delete_event($_[1]);
   } else {
      if (($_[1]->object->_type != TRAP) && 
          ($_[1]->object->_type != SNMPV2_TRAP)) 
      {
         # Schedule the timeout for the message
	 $_[0]->_object_schedule_event(
            $_[1], STATE_WAITING, $_[1]->object->timeout
         );
      } else {
         # Traps do not get a response, so we are done with the event
         $_[0]->_object_delete_event($_[1]);
      }
   }
}

sub _action_timeout
{

   # Check to see if there are any retries left

   if ($_[1]->object->_retries_left_now) {

      DEBUG_INFO("retry request-id = %s (%s), retries = %d",
         $_[1]->object->_fsm_request_id, $_[1]->object->hostname, 
         $_[1]->object->retries 
      );
      # Retransmit the message
      $_[0]->_action_send($_[1]);

   } else {

      DEBUG_INFO("timeout: request-id = %s (%s)",
         $_[1]->object->_request_id, $_[1]->object->hostname
      );
      # Set the error status
      $_[1]->object->_snmp_decode_error(
         "No response from agent on remote host '%s'", $_[1]->object->hostname 
      );
      # Inform the user via the callback
      $_[1]->object->_object_invoke_callback;
      $_[0]->_object_delete_event($_[1]);

   }
}

sub _action_read_data
{
   my ($this, $socket) = @_;

   # Validate the passed socket
   if ((!defined($socket)) || (!fileno($socket))) { 
      return $this->_object_error('Invalid socket'); 
   } 

   my $object = $this->{'_decode_object'};

   # Set the FSM's Net::SNMP object's socket equal to the socket
   $object->_socket($socket);

   # Clear any previous errors
   $object->_object_clear_error;

   # Read the data
   if (!defined($object->_udp_recv_buffer)) {
      return $this->_object_error("%s", $object->error);
   }

   # Decode the packet up to the VarBindList

   $object->_object_clear_snmp_message;

   $object->_type(GET_RESPONSE);
   if (!defined($object->_snmp_decode_message)) {
      return $this->_object_error("%s", $object->error);
   }
   if (!defined($object->_snmp_decode_pdu)) {
      return $this->_object_error("%s", $object->error);
   }

   # Now look for a matching waiting message based on request-id
   if (exists($this->{'_request_ids'}->{$object->_request_id})) {

      my $e = $this->{'_request_ids'}->{$object->_request_id};

      if ($e->state == STATE_WAITING) {

         DEBUG_INFO("response received: request-id = %s (%s)", 
            $e->object->_fsm_request_id, $e->object->hostname
         ); 
         # Now compare the response to sent message
         if (!defined($e->object->_snmp_compare_get_response($object))) {
            $e->object->_object_invoke_callback;
            return $this->_object_delete_event($e);
         }
         # Copy the remaining buffer over to the "real" object
         # and decode the VarBindList.
         $e->object->_object_buffer($object->_object_buffer);
         $e->object->_snmp_decode_var_bind_list;
         $e->object->_object_invoke_callback;
         return $this->_object_delete_event($e);

      } else {

         # We received a response for a request-id that was not
         # waiting for a response?  
 
         DEBUG_INFO("unexpected response, request-id = %d, state = %s",
            $e->object->_fsm_request_id, $e->state
         ); 
      }
   }

   $this->_object_error("Unknown request-id = %d", $object->_request_id);
}

sub _action_queue
{
   my ($this, $message) = @_;

   # Make sure that a Net::SNMP object was passed
   if (!defined($message) || ref($message) ne 'Net::SNMP') {
      return $this->_object_error('Invalid message type');
   }

   # Validate the socket status
   if ((!defined($message->_socket)) || (!fileno($message->_socket))) {
      return $this->_object_error('Socket is invalid');
   }

   # Copy the object, so that we can use it for retransmissions
   my $copy = $message->_object_copy;

   # Adjust the MTU of the decode object if necessary
   if ($copy->mtu > $this->{'_decode_object'}->mtu) {
      $this->{'_decode_object'}->mtu($copy->mtu);
   } 

   # Add a copy of the request-id to the copy
   $copy->_fsm_request_id($copy->_request_id);

   # Add the socket to the "readable" vector
   vec($this->{'_rin'}, fileno($copy->_socket), 1) = 1;

   # Add the socket to the list of sockets
   $this->{'_sockets'}->{fileno($copy->_socket)} = $copy->_socket;

   DEBUG_INFO("add request-id = %s (%s)", 
      $copy->_fsm_request_id, $copy->hostname
   );

   # Add the event 
   $this->_object_add_event($copy->_object_event_delay, $copy);
}


###
## Object specific methods/functions
###

sub _object_add_event
{
   my ($this, $time, $object) = @_;

   if ((@_ != 3) || ($time !~ /^\d+(\.\d+)?$/) || (!ref($object))) {
      return $this->_object_error('Invalid arguments');
   }

   # Create a new Finite State Machine Event object and add it to
   # queue.  The parameters passed to the Event constructor depend
   # on the current state of the FSM.  If the FSM is not currently
   # running, the event needs created such that it will get properly
   # initialized when the FSM is started.

   my $event = Net::SNMP::FSM::Event->new(
         \$_[0]->{'_event_queue_h'},
         \$_[0]->{'_event_queue_t'},
         ($_[0]->{'_active'} ? time() + $time : $time),
         ($_[0]->{'_active'} ? STATE_PENDING : STATE_INIT),    
         $object
   );

   if (!defined($event)) {
      die("FATAL: Unable to create new Event object");
      return $this->_object_error('Unable to create new Event object');
   }

   # Cache the request-id and return the Event.

   $this->{'_request_ids'}->{$object->_fsm_request_id} = $event;
}

sub _object_delete_event
{
   my ($this, $event) = @_;

   # An event is deleted by just removing it out of the queue.

   if ((@_ != 2) || (ref($event) ne 'Net::SNMP::FSM::Event')) {
      return $this->_object_error('Invalid arguments');
   }

   DEBUG_INFO("remove request-id = %s (%s)",
      $event->object->_fsm_request_id, $event->object->hostname
   );

   # Remove the entry from the request-id cache

   if (!delete($this->{'_request_ids'}->{$event->object->_fsm_request_id})) {
      $this->_object_error(
         "Request-id = %s not found", $event->object->_fsm_request_id
      );
      die("FATAL: Attempt to delete unknown request-id from cache");
   }

   # Have the Event delete itself from the queue
   $event->delete;
}

sub _object_schedule_event
{
   my ($this, $event, $state, $time) = @_; 

   # The scheduling of an event just changes the state and time that
   # the event is to occur.  The time passed to this method is expected
   # to be a delta time from the current time.

   if ((@_ != 4) || (ref($event) ne 'Net::SNMP::FSM::Event') 
        || ($time !~ /^\d+(\.\d+)?$/)) 
   {
      return $this->_object_error('Invalid arguments');
   }

   my @s = qw(STATE_INIT STATE_PENDING STATE_WAITING);
   DEBUG_INFO("delta = %f state = %s", $_[3], $s[$_[2]]);
   $event->state($state);         # The new state
   $event->time(time() + $time);  # The time passed is a delta from now

   $event;
}

sub _object_clear
{
   $_[0]->{'_active'}        = FALSE;
   $_[0]->{'_blocking'}      = TRUE;
   $_[0]->{'_event_queue_h'} = undef;
   $_[0]->{'_event_queue_t'} = undef;
   $_[0]->{'_request_ids'}   = {};
   $_[0]->{'_rin'}           = '';
   $_[0]->{'_sockets'}       = {};

   TRUE;
}

sub _object_error
{
   my ($this, $format, @message) = @_;

   if ($Net::SNMP::DEBUG) {
      printf("error: [%d] %s(): %s\n", 
         (caller(0))[2], (caller(1))[3], sprintf($format, @message) 
      );
   }

   undef;
}

# ============================================================================
1; # [end Net::SNMP::FSM]
# ============================================================================

package Net::SNMP::FSM::Event;

# $Id: SNMP_365.pm,v 1.1.1.1 2003/06/11 19:33:42 sartori Exp $
# $Source: /usr/local/cvsroot/ifgraph-0.4.10/lib/Net/SNMP_365.pm,v $

# Event object used by the Net::SNMP Finite State Machine

# Copyright (c) 2000 David M. Town <david.town@marconi.com>.
# All rights reserved.

# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself.

# ============================================================================

## Version of Net::SNMP::FSM::Event module

$Net::SNMP::FSM::Event::VERSION = 1.01;

## Import debug function

sub BEGIN
{
   *DEBUG_INFO = \&Net::SNMP::DEBUG_INFO;
}

# [public methods] -----------------------------------------------------------

sub new
{
   my ($class, $head, $tail, $time, $state, $object) = @_;

   if (!ref($head) || !ref($tail) || ($time !~ /^\d+(\.\d+)?$/)){
      return undef;
   }

   my $this = bless {
      '_time'     => $time,    # Event time
      '_state'    => $state,   # Event state
      '_object'   => $object,  # Event object
      '_head'     => $head,    # Reference to tree head
      '_tail'     => $tail,    # Reference to tree tail
      '_previous' => undef,    # Previous event
      '_next'     => undef,    # Next event
   }, $class;

   $this->_insert_by_time;
}

sub delete
{
   $_[0]->_delete;
}

sub state
{
   (@_ == 2) ? $_[0]->{'_state'} = $_[1] : $_[0]->{'_state'};
}

sub time
{
   # Since the entries are sorted by time, a change in time requires
   # the list to be re-sorted.  The quickest way to resort the list
   # is to delete the entry and re-add it?

   if ((@_ == 2) && ($_[1] =~ /^\d+(\.\d+)?$/)) {
      $_[0]->{'_time'} = $_[1];
      $_[0]->_delete;
      $_[0]->_insert_by_time;
   }

   $_[0]->{'_time'};
}

sub object
{
   $_[0]->{'_object'};
}


# [private methods] ----------------------------------------------------------

sub _insert_by_time
{
   my ($this) = @_;

   # If the head of the list is not defined, we _must_ be the only
   # entry in the list, so create a new head and tail reference.

   if (!defined(${$this->{'_head'}})) {
      DEBUG_INFO("created new head and tail [%s]", $this);
      return ${$this->{'_head'}} = ${$this->{'_tail'}} = $this;
   }

   # Estimate the midpoint of the list by calculating the average of
   # the time associated with the head and tail of the list.  Based
   # on this value either start at the head or tail of the list to
   # search for an insertion point for the new Event. 

   my $midpoint = ((${$this->{'_head'}}->{'_time'} +
                    ${$this->{'_tail'}}->{'_time'}) / 2);


   if ($this->{'_time'} >= $midpoint) {

      # Search backwards from the tail of the list

      for (my $e = ${$this->{'_tail'}}; defined($e); $e = $e->{'_previous'}) {
         if ($e->{'_time'} <= $this->{'_time'}) {
            $this->{'_previous'} = $e;
            $this->{'_next'} = $e->{'_next'};
            if ($e eq ${$this->{'_tail'}}) {
               DEBUG_INFO("modified tail [%s]", $this);
               ${$this->{'_tail'}} = $this;
            } else {
               DEBUG_INFO("inserted [%s] into list", $this);
            }
            return $e->{'_next'} = $e->{'_next'}->{'_previous'} = $this;
         }
      }

      DEBUG_INFO("added [%s] to head of list", $this);
      $this->{'_next'} = ${$this->{'_head'}};
      ${$this->{'_head'}} = ${$this->{'_head'}}->{'_previous'} = $this;

   } else {

      # Search forward from the head of the list

      for (my $e = ${$this->{'_head'}}; defined($e); $e = $e->{'_next'}) {
         if ($e->{'_time'} > $this->{'_time'}) {
            $this->{'_next'} = $e;
            $this->{'_previous'} = $e->{'_previous'};
            if ($e eq ${$this->{'_head'}}) {
               DEBUG_INFO("modified head [%s]", $this);
               ${$this->{'_head'}} = $this;
            } else {
               DEBUG_INFO("inserted [%s] into list", $this);
            }
            return $e->{'_previous'} = $e->{'_previous'}->{'_next'} = $this;
         }
      }

      DEBUG_INFO("added [%s] to tail of list", $this);
      $this->{'_previous'} = ${$this->{'_tail'}};
      ${$this->{'_tail'}} = ${$this->{'_tail'}}->{'_next'} = $this;

   }

}

sub _delete
{
   my ($this) = @_;

   if (defined($this->{'_previous'})) {
      $this->{'_previous'}->{'_next'} = $this->{'_next'};
   } elsif ($this eq ${$this->{'_head'}}) {
      if (defined(${$this->{'_head'}} = $this->{'_next'})) {
         DEBUG_INFO("defined new head [%s]", $this->{'_next'});
      } else {
         DEBUG_INFO("deleted [%s], list is now empty", $this);
         $this->{'_previous'} = $this->{'_next'} = ${$this->{'_tail'}} = undef;
         return $this;
      }
   } else {
      die("FATAL: Attempt to delete invalid Event head");
   }
 

   if (defined($this->{'_next'})) {
      $this->{'_next'}->{'_previous'} = $this->{'_previous'};
   } elsif ($this eq ${$this->{'_tail'}}) {
      DEBUG_INFO("defined new tail [%s]", $this->{'_previous'});
      ${$this->{'_tail'}} = $this->{'_previous'};
   } else {
      die("FATAL: Attempt to delete invalid Event tail");
   }

   $this->{'_previous'} = $this->{'_next'} = undef;
   DEBUG_INFO("deleted [%s]", $this);

   $this;
}

sub _debug_dump_contents
{
   if (!$Net::SNMP::DEBUG) { return $_[0]; }

   printf("Entry [%s]\n", $_[0]);
   printf("\tTime:     %d\n", $_[0]->{'_time'});
   printf("\tState:    %s\n", $_[0]->{'_state'});
   printf("\tObject:   %s\n", $_[0]->{'_object'});
   printf("\tHead:     %s\n", ${$_[0]->{'_head'}});
   printf("\tTail:     %s\n", ${$_[0]->{'_tail'}});
   printf("\tPrevious: %s\n",
      defined($_[0]->{'_previous'}) ? $_[0]->{'_previous'} : '<null>'
   );
   printf("\tNext:     %s\n",
      defined($_[0]->{'_next'}) ? $_[0]->{'_next'} : '<null>'
   );

   $_[0];
}

sub _debug_dump_list
{
   if (!$Net::SNMP::DEBUG) { return $_[0]; }

   if (!defined(${$_[0]->{'_head'}})) {
      DEBUG_INFO("list is empty");
      return $_[0];
   }

   DEBUG_INFO;

   for (my $e = ${$_[0]->{'_head'}}; defined($e); $e = $e->{'_next'}) {
      $e->_debug_dump_contents;
   }

   printf("\n");

   $_[0];
}

# ============================================================================
1; # [end Net::SNMP::FSM::Event]
# ============================================================================

__DATA__

###
## POD formatted documentation for Perl module Net::SNMP.
##
## $Id: SNMP_365.pm,v 1.1.1.1 2003/06/11 19:33:42 sartori Exp $
## $Source: /usr/local/cvsroot/ifgraph-0.4.10/lib/Net/SNMP_365.pm,v $
##
###

=head1 NAME

Net::SNMP - Simple Network Management Protocol

=head1 SYNOPSIS

The module Net::SNMP implements an object oriented interface to the Simple 
Network Management Protocol.  Perl applications can use the module to retrieve
or update information on a remote host using the SNMP protocol. Net::SNMP is 
implemented completely in Perl, requires no compiling, and uses only standard 
Perl modules. Both SNMPv1 and SNMPv2c (Community-Based SNMPv2) are supported 
by the module. The Net::SNMP module assumes that the user has a basic 
understanding of the Simple Network Management Protocol and related network 
management concepts.

=head1 DESCRIPTION 

The module Net::SNMP abstracts the intricate details of the Simple Network 
Management Protocol by providing a high level programming interface to the 
protocol.  Each Net::SNMP object provides a one-to-one mapping between a Perl 
object and a remote SNMP agent or manager.  Once an object is created, it can 
be used to perform all of the basic protocol exchange actions defined by SNMP. 

A Net::SNMP object can be created such that it has either "blocking" or 
"non-blocking" properties.  By default, the methods used to send SNMP messages 
do not return until the protocol exchange has completed successfully or a 
timeout period has expired. This behavior gives the object a "blocking" 
property because the flow of the code is stopped until the method returns.  

The optional named argument "B<-nonblocking>" can be passed to the object 
constructor with a true value to give the object "non-blocking" behavior.
A method invoked by a non-blocking object queues the SNMP message and returns
immediately allowing the flow of the code to continue. The queued SNMP messages
are not sent until an event loop is entered by calling the C<snmp_event_loop()>
method.  When the SNMP messages are sent, any response to the messages invokes
the subroutine defined by the user when the message was originally queued. The
event loop exits when all messages have been removed from the queue by either 
receiving a response or when the number of retries for the object has been 
exceeded.

=head2 Blocking Objects

The default behavior of the methods associated with a Net::SNMP object is to 
block the code flow until the method completes.  For methods that initiate a 
SNMP protocol exchange requiring a response, a hash reference containing the 
results of the query are returned. The undefined value is returned by all 
methods when a failure has occurred. The C<error()> method can be used to 
determine the cause of the failure.

The hash reference returned by a SNMP protocol exchange points to a hash 
constructed from the VarBindList contained in the SNMP GetResponse-PDU.  The 
hash is created using the ObjectName and the ObjectSyntax pairs in the 
VarBindList.  The keys of the hash consist of the OBJECT IDENTIFIERs in dotted 
notation corresponding to each ObjectName in the VarBindList.  The value of 
each hash entry is set equal to the value of the corresponding ObjectSyntax. 
This hash reference can also be retrieved using the C<var_bind_list()> method.

=head2 Non-blocking Objects

When a Net::SNMP object is created having non-blocking behavior, the invocation
of a method associated with the object returns immediately, allowing the flow of 
the code to continue.  When a method is invoked that would initiate a SNMP 
protocol exchange requiring a response, either a true value (i.e. 0x1) is 
returned immediately or the undefined value is returned if there was a failure.
The C<error()> method can be used to determine the cause of the failure.

=over

=item Callback Argument

Most methods associated with a non-blocking object have an optional named 
argument called "B<-callback>".  The B<-callback> argument expects a reference 
to a subroutine or to an array whose first element must be a reference to a 
subroutine.  The subroutine defined by the B<-callback> option is executed when
a response to a SNMP message is received, an error condition has occurred, or 
the number of retries for the message has been exceeded. 

When the B<-callback> argument only contains a subroutine reference, the 
subroutine is evaluated passing a copy of the original Net::SNMP object as the 
only parameter.  The copy of the object has all of the properties that the 
original object had when the message was queued, and will also contain the 
results of the SNMP protocol exchange.  If the B<-callback> argument was 
defined as an array reference, all elements in the array are passed to the 
subroutine after the copy of the Net::SNMP object.  The first element, which is
required to be a reference to a subroutine, is removed before the remaining 
arguments are passed to that subroutine.

Once one method is invoked with the B<-callback> argument, this argument stays 
with the object and is used by any further calls to methods using the 
B<-callback> option if the argument is absent.  The undefined value may be 
passed to the B<-callback> argument to delete the callback subroutine.

B<NOTE:> The subroutine being passed with the B<-callback> named argument 
should not cause blocking itself.  This will cause all the actions in the event
loop to be stopped, defeating the non-blocking property of the Net::SNMP 
module. 

=item Delay Argument

An optional argument B<-delay> can also be passed to non-blocking objects.  The
B<-delay> argument instructs the object to wait the number of seconds passed
to the argument before excuting the method.  The delay period starts when the
event loop is entered.  The B<-delay> parameter is applied to all methods
associated with the object once it is specified.  The delay value must be set 
back to 0 seconds to disable the delay parameter.

=back

The contents of the VarBindList contained in the SNMP GetResponse-PDU can be 
retrieved by calling the C<var_bind_list()> method associated with the copy of 
the original object.  The value returned by the C<var_bind_list()> method is a 
hash reference created using the ObjectName and the ObjectSyntax pairs in the 
VarBindList.  The keys of the hash consist of the OBJECT IDENTIFIERs in dotted 
notation corresponding to each ObjectName in the VarBindList.  The value of 
each hash entry is set equal to the value of the corresponding ObjectSyntax. 
The undefined value is returned if there has been a failure and the C<error()>
method may be used to determine the reason.

=head1 METHODS

Most methods associated with a Net::SNMP object take different parameters based
on the "blocking" or "non-blocking" property of the object.  When named 
arguments are used with methods, two different styles are supported. All 
examples in this documentation use the dashed-option style:

       $object->method(-argument => $value);

However, the IO:: style is also allowed:

       $object->method(Argument => $value);

=head2 session() - create a new Net::SNMP object

   ($session, $error) = Net::SNMP->session(
                           [-hostname    => $hostname,]
                           [-community   => $community,]
                           [-port        => $port,]
                           [-nonblocking => $nonblocking,]
                           [-version     => $version,]
                           [-timeout     => $seconds,]
                           [-retries     => $count,]
                           [-mtu         => $octets,]
                           [-translate   => $translate,]
                           [-debug       => $debug]
                        );

This is the constructor for Net::SNMP objects.  In scalar context, a
reference to a new Net::SNMP object is returned if the creation of the object
is successful.  In list context, a reference to a new Net::SNMP object and an 
empty error message string is returned.  If a failure occurs, the object 
reference is returned as the undefined value.  The error string may be used 
to determine the cause of the error.

The B<-hostname>, B<-community>, B<-port>, and B<-nonblocking> arguments are 
basic properties of a Net::SNMP object and cannot be changed after the object 
is created.  All other arguments have methods that allow their values to be 
modified after the Net::SNMP object has been created.  See the methods 
corresponding to these named arguments for their valid ranges and default 
values.

All arguments are optional and will take default values in the absence of a
corresponding named argument. 

=over  

=item *

The default value for the remote B<-hostname> is "localhost".  The hostname 
can either be a network hostname or the dotted IP address of the host. 

=item *

The default value for the SNMP B<-community> name is "public".

=item *

The default value for the destination UDP B<-port> number is 161.  This is 
the port on which hosts using default values expect to receive all SNMP 
messages except for traps.  Port number 162 is the default port used by hosts 
expecting to receive SNMP traps.

=item *

The default value for the B<-nonblocking> property is 0x0 (false).

=back

=head2 close() - clear the UDP socket reference, buffers, and errors

   $session->close;

This method clears the UDP socket reference, the errors, hash pointers, and 
buffers associated with the object.  Once closed, the Net::SNMP object can
no longer be used to send or received SNMP messages.

=head2 snmp_event_loop() - enter the non-blocking object event loop

   $session->snmp_event_loop;

This method enters the event loop associated with non-blocking Net::SNMP
objects.  The method exits when all queued SNMP messages have been responded
to or have timed out.  This method is also exported as the stand alone 
function C<snmp_event_loop()> by default (see L<"EXPORTS">).

=head2 get_request() - send a SNMP get-request to the remote agent

Blocking

   $response = $session->get_request(@oids);

Non-blocking

         $ok = $session->get_request(
                            [-callback   => sub {},]
                            [-delay      => $seconds,]
	         	    -varbindlist => \@oids
                         );

This method performs a SNMP get-request query to gather data from the remote
agent on the host associated with the Net::SNMP object.  The blocking form of
the method takes a list of OBJECT IDENTIFIERs in dotted notation. Each OBJECT 
IDENTIFER is placed into a single SNMP GetRequest-PDU in the same order that it
held in the original list.  When the object is in non-blocking mode, the list
is passed as an array reference to the B<-varbindlist> named argument.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no 
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=head2 get_next_request() - send a SNMP get-next-request to the remote agent

Blocking

   $response = $session->get_next_request(@oids);

Non-blocking

         $ok = $session->get_next_request(
                            [-callback   => sub {},]
                            [-delay      => $seconds,]
                            -varbindlist => \@oids
                         );

This method performs a SNMP get-next-request query to gather data from the 
remote agent on the host associated with the Net::SNMP object.  The blocking 
form of the method takes a list of OBJECT IDENTIFIERs in dotted notation. Each 
OBJECT IDENTIFER is placed into a single SNMP GetNextRequest-PDU in the same 
order that it held in the original list.  When the object is in non-blocking 
mode, the list is passed as an array reference to the B<-varbindlist> named 
argument.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=head2 set_request() - send a SNMP set-request to the remote agent

Blocking

   $response = $session->set_request(@oid_type_value);

Non-blocking

         $ok = $session->set_request(
                            [-callback   => sub {},]
                            [-delay      => $seconds,]
                            -varbindlist => \@oid_type_value
                         );

This method is used to modify data on the remote agent that is associated
with the Net::SNMP object using a SNMP set-request.  The blocking form of the
method takes a list of values consisting of groups of an OBJECT IDENTIFIER,
an object type, and the actual value to be set.  The OBJECT IDENTIFIERs in each 
trio are to be in dotted notation.  The object type is a byte corresponding to 
the ASN.1 type of value that is to be set.  Each of the supported types have 
been defined and are exported by the package by default (see L<"EXPORTS">).  
When the object is in non-blocking mode, the list is passed as an array 
reference to the B<-varbindlist> named argument.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=head2 trap() - send a SNMP trap to the remote manager

Blocking

   $value = $session->trap(
                         [-enterprise   => $oid,]
                         [-agentaddr    => $ipaddress,]
                         [-generictrap  => $generic,]
                         [-specifictrap => $specific,]
                         [-timestamp    => $timeticks,]
                         [-varbindlist  => \@oid_type_value]
                       );

Non-blocking

   $value = $session->trap(
                         [-delay        => $seconds,]
                         [-enterprise   => $oid,]
                         [-agentaddr    => $ipaddress,]
                         [-generictrap  => $generic,]
                         [-specifictrap => $specific,]
                         [-timestamp    => $timeticks,]
                         [-varbindlist  => \@oid_type_value]
                       );

This method sends a SNMP trap to the remote manager associated with the
Net::SNMP object.  All arguments are optional and will be given the following 
defaults in the absence of a corresponding named argument: 

=over 

=item *

The default value for the trap B<-enterprise> is "1.3.6.1.4.1", which 
corresponds to "iso.org.dod.internet.private.enterprises".  The enterprise 
value is expected to be an OBJECT IDENTIFER in dotted notation. 

=item *

The default value for the trap B<-agentaddr> is the local IP address from
the host on which the script is running.  The agent-addr is expected to
be an IpAddress in dotted notation.

=item *

The default value for the B<-generictrap> type is 6 which corresponds to 
"enterpriseSpecific".  The generic-trap types are defined and can be exported
upon request (see L<"EXPORTS">).

=item *

The default value for the B<-specifictrap> type is 0.  No pre-defined values
are available for specific-trap types.

=item *

The default value for the trap B<-timestamp> is the "uptime" of the script.  The
"uptime" of the script is the number of hundredths of seconds that have elapsed
since the script began running.  The time-stamp is expected to be a TimeTicks
number in hundredths of seconds.

=item *

The default value for the trap B<-varbindlist> is an empty array reference.
The variable-bindings are expected to be in an array format consisting of 
groups of an OBJECT IDENTIFIER, an object type, and the actual value of the 
object.  This is identical to the list expected by the C<set_request()> method.
The OBJECT IDENTIFIERs in each trio are to be in dotted notation.  The object 
type is a byte corresponding to the ASN.1 type for the value. Each of the 
supported types have been defined and are exported by default (see 
L<"EXPORTS">).

=back

Upon success, the number of bytes transmitted is returned when the object is
in blocking mode.  A true value is returned when successful in non-blocking
mode.  The undefined value is returned when a failure has occurred.  The
C<error()> method can be used to determine the cause of the failure. Since
there are no acknowledgements for Trap-PDUs, there is no way to determine if
the remote host actually received the trap.  

B<NOTE:> When the object is in non-blocking mode, the trap is not sent until 
the event loop is entered.

=head2 get_bulk_request() - send a SNMPv2 get-bulk-request to the remote agent

Blocking

   $response = $session->get_bulk_request(
                            [-nonrepeaters   => $nonrepeaters,]
                            [-maxrepetitions => $maxrepetitions,]
                            -varbindlist     => \@oids
                         );

Non-blocking

         $ok = $session->get_bulk_request(
                            [-callback       => sub {},]
                            [-delay          => $seconds,]
                            [-nonrepeaters   => $nonrepeaters,]
                            [-maxrepetitions => $maxrepetitions,]
                            -varbindlist     => \@oids
                         );

This method performs a SNMP get-bulk-request query to gather data from the
remote agent on the host associated with the Net::SNMP object.  All arguments 
are optional except B<-varbindlist> and will be given the following defaults 
in the absence of a corresponding named argument: 

=over 

=item *

The default value for the get-bulk-request B<-nonrepeaters> is 0.  The 
non-repeaters value specifies the number of variables in the 
variable-bindings list for which a single successor is to be returned.

=item *

The default value for the get-bulk-request B<-maxrepetitions> is 0. The
max-repetitions value specifies the number of successors to be returned for
the remaining variables in the variable-bindings list.

=item *

The B<-varbindlist> argument expects an array reference consisting of a list of
OBJECT IDENTIFIERs in dotted notation.  Each OBJECT IDENTIFER is placed into a 
single SNMP GetBulkRequest-PDU in the same order that it held in the original 
list.

=back

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv2c.

=head2 inform_request() - send a SNMPv2 inform-request to the remote manager

Blocking

   $response = $session->inform_request(@oid_type_value);

Non-blocking

         $ok = $session->inform_request(
                            [-callback   => sub {},]
                            [-delay      => $seconds,]
                            -varbindlist => \@oid_type_value
                         );

This method is used to provide management information to the remote manager
associated with the Net::SNMP object using a SNMPv2 inform-request.  In 
blocking mode, the method takes a list of values consisting of groups of an 
OBJECT IDENTIFIER, an object type, and the actual value to be defined.  The 
OBJECT IDENTIFIERs in each trio are to be in dotted notation.  The object type
is a byte corresponding to the ASN.1 type of value that is identified. Each of
the supported types have been defined and are exported by the package by 
default (see L<"EXPORTS">).  When the object is in non-blocking mode, the 
list is passed as an array reference to the B<-varbindlist> named argument.

The first two variable-bindings fields in the inform-request are specified
by SNMPv2 and should be:

=over

=item *

sysUpTime.0 - ['1.3.6.1.2.1.1.3.0', TIMETICKS, $timeticks] 

=item *

snmpTrapOID.0 - ['1.3.6.1.6.3.1.1.4.1.0', OBJECT_IDENTIFIER, $oid]

=back

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv2c.

=head2 snmpv2_trap() - send a SNMPv2 snmpV2-trap to the remote manager

Blocking

   $response = $session->snmpv2_trap(@oid_type_value);

Non-blocking

         $ok = $session->snmpv2_trap(
                            [-delay      => $seconds,]
                            -varbindlist => \@oid_type_value
                         );

This method sends a SNMPv2 snmpV2-trap to the remote manager associated with 
the Net::SNMP object. In blocking mode, the method takes a list of values 
consisting of groups of an OBJECT IDENTIFIER, an object type, and the actual 
value to be defined. The OBJECT IDENTIFIERs in each trio are to be in dotted 
notation.  The object type is a byte corresponding to the ASN.1 type of value 
that is identified. Each of the supported types have been defined and are 
exported by the package by default (see L<"EXPORTS">).  When the object is in 
non-blocking mode, the list is passed as an array reference to the 
B<-varbindlist> named argument. 

The first two variable-bindings fields in the snmpV2-trap are specified by
SNMPv2 and should be:

=over

=item *

sysUpTime.0 - ['1.3.6.1.2.1.1.3.0', TIMETICKS, $timeticks]

=item *

snmpTrapOID.0 - ['1.3.6.1.6.3.1.1.4.1.0', OBJECT_IDENTIFIER, $oid]

=back

Upon success, the number of bytes transmitted is returned when the object is
in blocking mode.  A true value is returned when in successful in non-blocking 
mode.  The undefined value is returned when a failure has occurred.  The 
C<error()> method can be used to determine the cause of the failure. Since
there are no acknowledgements for SNMPv2-Trap-PDUs, there is no way to 
determine if the remote host actually received the snmpV2-trap.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv2c.

B<NOTE:> When the object is in non-blocking mode, the snmpV2-trap is not sent 
until the event loop is entered.

=head2 get_table() - retrieve a table from the remote agent

Blocking

   $response = $session->get_table($oid);

Non-blocking

         $ok = $session->get_table(
                            -baseoid   => $oid,
                            [-callback => sub {},]
                            [-delay    => $seconds]
                         );

This method performs repeated SNMP get-next-request or get-bulk-request 
(when using SNMPv2c) queries to gather data from the remote agent on the host 
associated with the Net::SNMP object.  In blocking mode, the method takes a 
single OBJECT IDENTIFIER which is used as the base object for the SNMP 
requests.  Repeated SNMP requests are issued until the OBJECT IDENTIFER in 
the response is no longer a subtree of the base OBJECT IDENTIFIER.  When the 
object is in non-blocking mode, the OBJECT IDENTIFIER must be passed to the 
B<-baseoid> named argument.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

B<WARNING:> Results from this method can become very large if the base
OBJECT IDENTIFIER is close to the root of the SNMP MIB tree.

=head2 version() - set or get the SNMP version for the object

   $rfc_version = $session->version([$version]);

This method is used to set or get the current SNMP version associated with
the Net::SNMP object.  The module supports SNMP version-1 (SNMPv1) and SNMP 
version-2c (SNMPv2c).  The default version used by the module is SNMP 
version-1.

The method accepts the digit '1' or the string 'SNMPv1' for SNMP version-1 and
the digit '2', or the strings '2c', 'SNMPv2', or 'SNMPv2c' for SNMP version-2c.
The undefined value is returned upon an error and the C<error()> method may 
be used to determine the cause.

The method returns the current value for the SNMP version.  The returned value
is the corresponding version number defined by the RFCs for the protocol 
version field (i.e. SNMPv1 == 0 and SNMPv2c == 1).

=head2 error() - get the current error message from the object

   $error_message = $session->error;

This method returns a text string explaining the reason for the last error.
An empty string is returned if no error has occurred.

=head2 hostname() - get the associated hostname from the object

   $hostname = $session->hostname;

This method returns the hostname string that is associated with the object.

=head2 error_status() - get the current SNMP error-status from the object

   $error_status = $session->error_status;

This method returns the numeric value of the error-status contained in the 
last SNMP GetResponse-PDU.

=head2 error_index() - get the current SNMP error-index from the object

   $error_index = $session->error_index;

This method returns the numeric value of the error-index contained in the 
last SNMP GetResponse-PDU.

=head2 var_bind_list() - get the hash reference to the last SNMP response

   $response = $session->var_bind_list;

This method returns a hash reference created using the ObjectName and the 
ObjectSyntax pairs in the VarBindList of the last SNMP GetResponse-PDU received
by the object. The keys of the hash consist of the OBJECT IDENTIFIERs in dotted
notation corresponding to each ObjectName in the VarBindList.  If any OBJECT 
IDENTIFIERs passed to the method began with a leading dot, all of the OBJECT 
IDENTIFIER hash keys will be prefixed with a leading dot.  The value of each 
hash entry is set equal to the value of the corresponding ObjectSyntax.  The 
undefined value is returned if there has been a failure and the C<error()> 
method may be used to determine the reason.

=head2 timeout() - set or get the current timeout period for the object 

   $seconds = $session->timeout([$seconds]);

This method returns the current value for the UDP timeout for the Net::SNMP
object.  This value is the number of seconds that the object will wait for a
response from the agent on the remote host.  The default timeout is 5.0
seconds.

If a parameter is specified, the timeout for the object is set to the provided
value if it falls within the range 1.0 to 60.0 seconds.  The undefined value
is returned upon an error and the C<error()> method may be used to determine
the cause.

=head2 retries() - set or get the current retry count for the object

   $count = $session->retries([$count]);

This method returns the current value for the number of times to retry
sending a SNMP message to the remote host.  The default number of retries
is 1.

If a parameter is specified, the number of retries for the object is set to
the provided value if it falls within the range 0 to 20. The undefined value
is returned upon an error and the C<error()> method may be used to determine 
the cause.

=head2 mtu() - set or get the current MTU for the object

   $octets = $session->mtu([$octets]);

This method returns the current value for the Maximum Transport Unit for the
Net::SNMP object.  This value is the largest value in octets for an SNMP
message that can be transmitted or received by the object.  The default
MTU is 1500 octets.

If a parameter is specified, the Maximum Transport Unit is set to the provided
value if it falls within the range 484 to 65535 octets.  The undefined value
is returned upon an error and the C<error()> method may be used to determine
the cause.

=head2 translate() - enable or disable the translation mode for the object

   $mask = $session->translate([$mode]);

   or

   $mask = $session->translate([ 
                        [ # Perl anonymous ARRAY reference 
                           ['-all'            => $mode1,]
                           ['-octetstring     => $mode2,]
                           ['-null'           => $mode3,]
                           ['-timeticks'      => $mode4,]
                           ['-opaque'         => $mode5,]
                           ['-nosuchobject'   => $mode6,] 
                           ['-nosuchinstance' => $mode7,]
                           ['-endofmibview'   => $mode8,]
                           ['-unsigned'       => $mode9]  
                        ]
                     ]);
   

When the object decodes the GetResponse-PDU that is returned in response to
a SNMP message, certain values are translated into a more "human readable"
form.  By default the following translations occur: 

=over 

=item *

OCTET STRINGs and Opaques containing non-printable characters are converted 
into a hexadecimal representation prefixed with "0x". 

=item *

TimeTicks integer values are converted to a time format.

=item *

NULL values return the string "NULL" instead of an empty string.

=item *

noSuchObject exception values return the string "noSuchObject" instead of an
empty string.  If translation is not enabled, the SNMP error-status field
is set to 128 which is equal to the exported definition NOSUCHOBJECT (see 
L<"EXPORTS">).

=item *

noSuchInstance exception values return the string "noSuchInstance" instead of 
an empty string.  If translation is not enabled, the SNMP error-status field
is set to 129 which is equal to the exported definition NOSUCHINSTANCE (see 
L<"EXPORTS">).

=item *

endOfMibView exception values return the string "endOfMibView" instead of an
empty string.  If translation is not enabled, the SNMP error-status field
is set to 130 which is equal to the exported definition ENDOFMIBVIEW (see 
L<"EXPORTS">).

=item *

Counter, Gauges, and TimeTick values that have been incorrectly encoded as
signed negative values are returned as unsigned values.  

=back

The C<translate()> method can be invoked with two different types of arguments.

If the argument passed is any Perl variable type except an array reference,
the translation mode for all ASN.1 type is set to either enabled or disabled 
depending on the value of the passed parameter.  Any value that Perl would 
treat as a true value will set the mode to be enabled for all types, while a 
false value will disable translation for all types.

A reference to an array can be passed to the C<translate()> method in order to
defined the translation mode on a per ASN.1 type basis.  The array is expected
to contain a list of named argument pairs for each ASN.1 type that is to
be modified.  The arguments in the list are applied in the order that they
are passed in via the array.  Arguments at the end of the list supercede 
those passed earlier in the list.  The argument "-all" can be used to specify
that the mode is to apply to all ASN.1 types.  Only the arguments for the 
ASN.1 types that are to be modified need to be included in the list.

The C<translate()> method returns a bit mask indicating which ASN.1 types
are to be translated.  Definitions of the bit to ASN.1 type mappings can be
exported using the ":translate" tag (see L<"EXPORTS">).  The undefined value 
is returned upon an error and the C<error()> method may be used to determine 
the cause.


=head2 debug() - set or get the debug mode for the module 

   $mode = $session->debug([$mode]);

This method is used to enable or disable debugging for the Net::SNMP module. By
default, debugging is off.  If a parameter is specified, the debug mode is set
to either enabled or disabled depending on the value of the passed parameter. 
Any value that Perl would treat as a true value will set the mode to be 
enabled, while a false value will disable debugging.  The current state of the 
debugging mode is returned by the method.  Debugging can also be enabled using
the stand alone function C<snmp_debug()>.  This function can be exported by
request (see L<"EXPORTS">).  

=head1 FUNCTIONS

=head2 oid_context_match() - determine if an OID has a specified MIB context 

   $value = oid_context_match($base_oid, $oid);

This function takes two OBJECT IDENTIFIERs in dotted notation and returns a
true value (i.e. 0x1) if the second OBJECT IDENTIFIER is equal to or is a 
subtree of the first OBJECT IDENTIFIER in the SNMP Management Information Base 
(MIB).  This function can be used in conjunction with the C<get-next-request()>
or C<get-bulk-request()> methods to determine when a OBJECT IDENTIFIER in the 
GetResponse-PDU is no longer in the desired MIB context.

=head2 oid_lex_sort() - sort a list of OBJECT IDENTIFIERs lexicographically

   @sorted_oids = oid_lex_sort(@oids);

This function takes a list of OBJECT IDENTIFIERs in dotted notation and returns
the listed sorted in lexicographical order.

=head2 ticks_to_time() - convert TimeTicks to formatted time

   $time = ticks_to_time($timeticks);

This function takes an ASN.1 TimeTicks value and returns a string representing
the time defined by the value.  The TimeTicks value is expected to be a 
non-negative integer value representing the time in hundredths of a second since
some epoch.  The returned string will display the time in days, hours, and 
seconds format according to the value of the TimeTicks argument.

=head1 EXPORTS

=over

=item Default

INTEGER, INTEGER32, OCTET_STRING, NULL, OBJECT_IDENTIFIER, IPADDRESS, COUNTER,
COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, OPAQUE, COUNTER64, 
NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW, snmp_event_loop

=item Exportable

INTEGER, INTEGER32, OCTET_STRING, NULL, OBJECT_IDENTIFIER, SEQUENCE, 
IPADDRESS, COUNTER, COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, OPAQUE, 
COUNTER64, NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW, GET_REQUEST, 
GET_NEXT_REQUEST, GET_RESPONSE, SET_REQUEST, TRAP, GET_BULK_REQUEST, 
INFORM_REQUEST, SNMPV2_TRAP, COLD_START, WARM_START, LINK_DOWN, LINK_UP, 
AUTHENTICATION_FAILURE, EGP_NEIGHBOR_LOSS, ENTERPRISE_SPECIFIC, 
SNMP_VERSION_1, SNMP_VERSION_2C, SNMP_PORT, SNMP_TRAP_PORT, snmp_debug, 
snmp_event_loop, oid_context_match, oid_lex_sort, ticks_to_time,
TRANSLATE_NONE, TRANSLATE_OCTET_STRING, TRANSLATE_NULL, TRANSLATE_TIMETICKS,
TRANSLATE_OPAQUE, TRANSLATE_NOSUCHOBJECT, TRANSLATE_NOSUCHINSTANCE,
TRANSLATE_ENDOFMIBVIEW, TRANSLATE_UNSIGNED, TRANSLATE_ALL

=item Tags

=over 

=item :asn1

INTEGER, INTEGER32, OCTET_STRING, NULL, OBJECT_IDENTIFIER, SEQUENCE, 
IPADDRESS, COUNTER, COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, OPAQUE, 
COUNTER64, NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW, GET_REQUEST, 
GET_NEXT_REQUEST, GET_RESPONSE, SET_REQUEST, TRAP, GET_BULK_REQUEST, 
INFORM_REQUEST, SNMPV2_TRAP

=item :generictrap

COLD_START, WARM_START, LINK_DOWN, LINK_UP, AUTHENTICATION_FAILURE,
EGP_NEIGHBOR_LOSS, ENTERPRISE_SPECIFIC

=item :snmp

SNMP_VERSION_1, SNMP_VERSION_2C, SNMP_PORT, SNMP_TRAP_PORT, snmp_debug, 
snmp_event_loop, oid_context_match, oid_lex_sort, ticks_to_time

=item :translate

TRANSLATE_NONE, TRANSLATE_OCTET_STRING, TRANSLATE_NULL, TRANSLATE_TIMETICKS,
TRANSLATE_OPAQUE, TRANSLATE_NOSUCHOBJECT, TRANSLATE_NOSUCHINSTANCE, 
TRANSLATE_ENDOFMIBVIEW, TRANSLATE_UNSIGNED, TRANSLATE_ALL

=item :ALL

All of the above exportable items.

=back

=back

=head1 EXAMPLES

=head2 Blocking get-request for sysUpTime

This example gets the sysUpTime from a remote host:

   #! /usr/local/bin/perl

   use strict;
   use vars qw($session $error $response);

   use Net::SNMP;

   ($session, $error) = Net::SNMP->session(
      -hostname  => shift || 'localhost',
      -community => shift || 'public',
      -port      => shift || 161 
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit 1;
   }

   my $sysUpTime = '1.3.6.1.2.1.1.3.0';

   if (!defined($response = $session->get_request($sysUpTime))) {
      printf("ERROR: %s.\n", $session->error());
      $session->close();
      exit 1;
   }

   printf("sysUpTime for host '%s' is %s\n", 
      $session->hostname(), 
      $response->{$sysUpTime}
   );

   $session->close();

   exit 0;

=head2 Blocking set-request of sysContact 

This example sets the sysContact information on the remote host to "Help Desk":

   #! /usr/local/bin/perl

   use strict;
   use vars qw($session $error $response);

   use Net::SNMP;

   ($session, $error) = Net::SNMP->session(
      -hostname  => shift || 'localhost',
      -community => shift || 'private',
      -port      => shift || 161
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit 1;
   }

   my $sysContact = '1.3.6.1.2.1.1.4.0';
   my $contact    = 'Help Desk';

   $response = $session->set_request($sysContact, OCTET_STRING, $contact);

   if (!defined($response)) {
      printf("ERROR: %s.\n", $session->error());
      $session->close();
      exit 1;
   }

   printf("sysContact for host '%s' set to '%s'\n", 
      $session->hostname(),
      $response->{$sysContact}
   );

   $session->close();

   exit 0;

=head2 Non-blocking get-request for sysUpTime on multiple hosts

This example polls several hosts for their sysUpTime using non-blocking 
objects and reports a warning if this value is less than the value from
the last poll:

   #! /usr/local/bin/perl

   use strict;
   use vars qw(@hosts @sessions $MAX_POLLS $INTERVAL $EPOC);

   use Net::SNMP qw(snmp_event_loop ticks_to_time);

   # List of hosts to poll

   @hosts = qw(.1.1.1 1.1.1.2 localhost);

   # Poll interval (in seconds).  This value should be greater than
   # the number of retries times the timeout value.

   $INTERVAL = 60;

   # Maximum number of polls after initial poll

   $MAX_POLLS = 10;

   # Create a session for each host
   foreach (@hosts) {
      my ($session, $error) = Net::SNMP->session(
         -hostname    => $_,
         -nonblocking => 0x1,   # Create non-blocking objects
         -translate   => [
            -timeticks => 0x0   # Turn off so sysUpTime is numeric
         ]  
      );
      if (!defined($session)) {
         printf("ERROR: %s.\n", $error);
         foreach (@sessions) { $_->[0]->close(); }
         exit 1;
      }

      # Create an array of arrays which contains the new object, 
      # the last sysUpTime, and the total number of polls.

      push(@sessions, [$session, 0, 0]);
   }

   my $sysUpTime = '1.3.6.1.2.1.1.3.0';

   # Queue each of the queries for sysUpTime
   foreach (@sessions) {
      $_->[0]->get_request(
          -varbindlist => [$sysUpTime],
          -callback    => [\&validate_sysUpTime_cb, \$_->[1], \$_->[2]]
      );
   }

   # Define a reference point for all of the polls
   $EPOC = time();

   # Enter the event loop
   snmp_event_loop();

   # Not necessary, but it is nice to clean up after yourself
   foreach (@sessions) { $_->[0]->close(); }

   exit 0;


   sub validate_sysUpTime_cb
   {
      my ($this, $last_uptime, $num_polls) = @_;

      if (!defined($this->var_bind_list())) {

         printf("%-15s  ERROR: %s\n", $this->hostname(), $this->error());

      } else {
   
         # Validate the sysUpTime

         my $uptime = $this->var_bind_list()->{$sysUpTime};
         if ($uptime < ${$last_uptime}) {
            printf("%-15s  WARNING: %s is less than %s\n",
               $this->hostname(), 
               ticks_to_time($uptime), 
               ticks_to_time(${$last_uptime})
            );
         } else {
            printf("%-15s  Ok (%s)\n", 
               $this->hostname(), 
               ticks_to_time($uptime)
            );
         }

         # Store the new sysUpTime
         ${$last_uptime} = $uptime;

      }

      # Queue the next message if we have not reach MAX_POLLS

      if (++${$num_polls} <= $MAX_POLLS) {
         my $delay = (($INTERVAL * ${$num_polls}) + $EPOC) - time();
         $this->get_request(
            -delay       => ($delay >= 0) ? $delay : 0,
            -varbindlist => [$sysUpTime],
            -callback    => [\&validate_sysUpTime_cb, $last_uptime, $num_polls]
         );
      }

      $this->error_status();
   }


=head1 AUTHOR

David M. Town <david.town@marconi.com>

=head1 ACKNOWLEDGMENTS

The original concept for this module was based on F<SNMP_Session.pm> written 
by Simon Leinen <simon@switch.ch>.

The Abstract Syntax Notation One (ASN.1) encode and decode methods were 
derived by example from the CMU SNMP package whose copyright follows: 
Copyright (c) 1988, 1989, 1991, 1992 by Carnegie Mellon University.  
All rights reserved. 

=head1 COPYRIGHT

Copyright (c) 1998-2001 David M. Town.  All rights reserved.  This program 
is free software; you may redistribute it and/or modify it under the same
terms as Perl itself.

