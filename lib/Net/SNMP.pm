# -*- mode: perl -*-
# ============================================================================

package Net::SNMP;

# $Id: SNMP.pm,v 1.1.1.1 2003/06/11 19:33:44 sartori Exp $

# Copyright (c) 1998-2002 David M. Town <dtown@cpan.org>
# All rights reserved.

# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself.

# Release 4.0.0 of the Net::SNMP module is dedicated to those who died in 
# the September 11, 2001 terrorist attacks on the United States of America.

# ============================================================================

=head1 NAME

Net::SNMP - Object oriented interface to SNMP 

=head1 SYNOPSIS

The Net::SNMP module implements an object oriented interface to the Simple 
Network Management Protocol.  Perl applications can use the module to retrieve 
or update information on a remote host using the SNMP protocol.  The module 
supports SNMP version-1, SNMP version-2c (Community-Based SNMPv2), and SNMP 
version-3. The Net::SNMP module assumes that the user has a basic understanding
of the Simple Network Management Protocol and related network management 
concepts.

=head1 DESCRIPTION

The Net::SNMP module abstracts the intricate details of the Simple Network
Management Protocol by providing a high level programming interface to the
protocol.  Each Net::SNMP object provides a one-to-one mapping between a Perl
object and a remote SNMP agent or manager.  Once an object is created, it can
be used to perform the basic protocol exchange actions defined by SNMP.

A Net::SNMP object can be created such that it has either "blocking" or
"non-blocking" properties.  By default, the methods used to send SNMP messages
do not return until the protocol exchange has completed successfully or a
timeout period has expired. This behavior gives the object a "blocking"
property because the flow of the code is stopped until the method returns.

The optional named argument B<-nonblocking> can be passed to the object
constructor with a true value to give the object "non-blocking" behavior.
A method invoked by a non-blocking object queues the SNMP message and returns
immediately, allowing the flow of the code to continue. The queued SNMP 
messages are not sent until an event loop is entered by calling the 
C<snmp_dispatcher()> method.  When the SNMP messages are sent, any response to 
the messages invokes the subroutine defined by the user when the message was 
originally queued. The event loop exits when all messages have been removed 
from the queue by either receiving a response, or by exceeding the number of 
retries at the Transport Layer.

=head2 Blocking Objects

The default behavior of the methods associated with a Net::SNMP object is to
block the code flow until the method completes.  For methods that initiate a
SNMP protocol exchange requiring a response, a hash reference containing the
results of the query is returned. The undefined value is returned by all
methods when a failure has occurred. The C<error()> method can be used to
determine the cause of the failure.

The hash reference returned by a SNMP protocol exchange points to a hash
constructed from the VarBindList contained in the SNMP response message.  The
hash is created using the ObjectName and the ObjectSyntax pairs in the
VarBindList.  The keys of the hash consist of the OBJECT IDENTIFIERs in dotted
notation corresponding to each ObjectName in the VarBindList.  The value of
each hash entry is set equal to the value of the corresponding ObjectSyntax.
This hash reference can also be retrieved using the C<var_bind_list()> method.

=head2 Non-blocking Objects

When a Net::SNMP object is created having non-blocking behavior, the invocation
of a method associated with the object returns immediately, allowing the flow 
of the code to continue.  When a method is invoked that would initiate a SNMP
protocol exchange requiring a response, either a true value (i.e. 0x1) is
returned immediately or the undefined value is returned if there was a failure.
The C<error()> method can be used to determine the cause of the failure.

The contents of the VarBindList contained in the SNMP response message can be
retrieved by calling the C<var_bind_list()> method using the object reference
passed as the first argument to the callback.  The value returned by the 
C<var_bind_list()> method is a hash reference created using the ObjectName and
the ObjectSyntax pairs in the VarBindList.  The keys of the hash consist of 
the OBJECT IDENTIFIERs in dotted notation corresponding to each ObjectName 
in the VarBindList.  The value of each hash entry is set equal to the value of
the corresponding ObjectSyntax. The undefined value is returned if there has 
been a failure and the C<error()> method may be used to determine the reason.

=cut

# ============================================================================

use strict;

## Validate the version of Perl

BEGIN 
{
   die('Perl version 5.6.0 or greater is required') if ($] < 5.006);
}

## Version of the Net::SNMP module

our $VERSION = v4.0.3;

## Load our modules

use Net::SNMP::Dispatcher();
use Net::SNMP::PDU qw(:ALL);
use Net::SNMP::Security();
use Net::SNMP::Transport::UDP qw(:ports);

## Handle exporting of symbols

use Exporter();

our @ISA = qw(Exporter);

our @ASN1 = qw(
   INTEGER INTEGER32 OCTET_STRING OBJECT_IDENTIFIER IPADDRESS COUNTER 
   COUNTER32 GAUGE GAUGE32 UNSIGNED32 TIMETICKS OPAQUE COUNTER64 NOSUCHOBJECT 
   NOSUCHINSTANCE ENDOFMIBVIEW
);

our @ASN1_PDU = qw(
   GET_REQUEST GET_NEXT_REQUEST GET_RESPONSE SET_REQUEST TRAP
   GET_BULK_REQUEST INFORM_REQUEST SNMPV2_TRAP
);

our @DEBUG = qw(
   DEBUG_ALL DEBUG_NONE DEBUG_MESSAGE DEBUG_TRANSPORT DEBUG_DISPATCHER
   DEBUG_PROCESSING DEBUG_SECURITY snmp_debug
);

our @GENERICTRAP = qw(
   COLD_START WARM_START LINK_DOWN LINK_UP AUTHENTICATION_FAILURE
   EGP_NEIGHBOR_LOSS ENTERPRISE_SPECIFIC
);

our @SNMP = qw(
   SNMP_VERSION_1 SNMP_VERSION_2C SNMP_VERSION_3 SNMP_PORT SNMP_TRAP_PORT 
   snmp_debug oid_base_match oid_context_match oid_lex_sort ticks_to_time
);

our @TRANSLATE = qw(
   TRANSLATE_NONE TRANSLATE_OCTET_STRING TRANSLATE_NULL TRANSLATE_TIMETICKS
   TRANSLATE_OPAQUE TRANSLATE_NOSUCHOBJECT TRANSLATE_NOSUCHINSTANCE
   TRANSLATE_ENDOFMIBVIEW TRANSLATE_UNSIGNED TRANSLATE_ALL
);

our @EXPORT    = (@ASN1, 'snmp_dispatcher', 'snmp_event_loop');
our @EXPORT_OK = (
   @ASN1_PDU, @DEBUG, @GENERICTRAP, @SNMP, @TRANSLATE, 'SEQUENCE', 'NULL', 
   'snmp_dispatch_once'
);

our %EXPORT_TAGS = (
   asn1        => [@ASN1, @ASN1_PDU, 'SEQUENCE', 'NULL'],
   debug       => [@DEBUG],
   generictrap => [@GENERICTRAP],
   snmp        => [@SNMP, 'snmp_dispatcher', 'snmp_event_loop'],
   translate   => [@TRANSLATE],
   ALL         => [@EXPORT, @EXPORT_OK]
);

## Debugging bit masks

sub DEBUG_ALL()        { 0xff }  # All
sub DEBUG_NONE()       { 0x00 }  # None
sub DEBUG_MESSAGE()    { 0x02 }  # Message/PDU encoding/decoding
sub DEBUG_TRANSPORT()  { 0x04 }  # Transport Layer
sub DEBUG_DISPATCHER() { 0x08 }  # Dispatcher
sub DEBUG_PROCESSING() { 0x10 }  # Message Processing
sub DEBUG_SECURITY()   { 0x20 }  # Security

## Package variables

our $DEBUG = DEBUG_NONE;         # Debug mask 

our $DISPATCHER;                 # Dispatcher instance

our $BLOCKING = 0;               # Count of blocking objects

our $NONBLOCKING = 0;            # Count of non-blocking objects

BEGIN
{
   # Validate the creation of the Dispatcher object. 

   if (!defined($DISPATCHER = Net::SNMP::Dispatcher->instance)) {
      die('FATAL: Failed to create Dispatcher instance');
   }
}

# [public methods] -----------------------------------------------------------

=head1 METHODS

When named arguments are expected by the methods, two different styles are 
supported.  All examples in this documentation use the dashed-option style:

       $object->method(-argument => $value);

However, the IO:: style is also allowed:

       $object->method(Argument => $value);

=over 

=item Non-blocking Objects Arguments

When a Net::SNMP object has been created with a "non-blocking" property, most
methods that generate a SNMP message take additional arguments to support this
property.

=over

=item Callback

Most methods associated with a non-blocking object have an optional named
argument called B<-callback>.  The B<-callback> argument expects a reference
to a subroutine or to an array whose first element must be a reference to a
subroutine.  The subroutine defined by the B<-callback> option is executed when
a response to a SNMP message is received, an error condition has occurred, or
the number of retries for the message has been exceeded.

When the B<-callback> argument only contains a subroutine reference, the
subroutine is evaluated passing a reference to the original Net::SNMP object 
as the only parameter.  If the B<-callback> argument was defined as an array
reference, all elements in the array are passed to subroutine after the
reference to the Net::SNMP object.  The first element, which is required to be
a reference to a subroutine, is removed before the remaining arguments are 
passed to that subroutine.

Once one method is invoked with the B<-callback> argument, this argument stays
with the object and is used by any further calls to methods using the
B<-callback> option if the argument is absent.  The undefined value may be
passed to the B<-callback> argument to delete the callback.

B<NOTE:> The subroutine being passed with the B<-callback> named argument
should not cause blocking itself.  This will cause all the actions in the event
loop to be stopped, defeating the non-blocking property of the Net::SNMP
module.

=item Delay

An optional argument B<-delay> can also be passed to non-blocking objects.  The
B<-delay> argument instructs the object to wait the number of seconds passed
to the argument before executing the SNMP protocol exchange.  The delay period 
starts when the event loop is entered.  The B<-delay> parameter is applied to 
all methods associated with the object once it is specified.  The delay value 
must be set back to 0 seconds to disable the delay parameter. 

=back

=item SNMPv3 Arguments

RFC 2575 defines the View-based Access Control Model for SNMP which allows an
administrator to restrict access to a specific MIB view.  Part of this access 
control includes the contextEngineID and contextName which are part of a
SNMPv3 scopedPDU.  All methods that generate a SNMP message optionally take
a B<-contextengineid> and B<-contextname> argument to configure these fields.

=over

=item Context Engine ID

The B<-contextengineid> argument expects a hexadecimal string representing
the desired contextEngineID.  The string must be 10 to 64 characters (5 to 
32 octets) long and can be prefixed with an optional "0x".  Once the 
B<-contextengineid> is specified it stays with the object until it is changed 
again or reset to default by passing in the undefined value.  By default, the 
contextEngineID is set to match the authoritativeEngineID of the authoritative
SNMP engine.

=item Context Name

The contextName is passed as a string which must be 0 to 32 octets in length 
using the B<-contextname> argument.  The contextName stays with the object 
until it is changed.  The contextName defaults to an empty string which 
represents the "default" context.

=back

=back

=cut

sub new
{
   my ($class, %argv) = @_;

   # Create a new data structure for the object
   my $this = bless {
        '_callback'          =>  undef,           # Callback
        '_context_engine_id' =>  undef,           # contextEngineID
        '_context_name'      =>  undef,           # contextName
        '_delay'             =>  0,               # Message delay
        '_hostname'          =>  '',              # Hostname
        '_discovery_queue'   =>  [],              # Pending message queue
        '_error'             =>  undef,           # Error message
        '_nonblocking'       =>  FALSE,           # Blocking/non-blocking flag
        '_pdu'               =>  undef,           # Message/PDU object
        '_security'          =>  undef,           # Security model
        '_translate'         =>  TRANSLATE_ALL,   # Translation mask 
        '_transport'         =>  undef,           # Transport model
        '_transport_argv'    =>  [],              # Transport constructor argv
        '_version'           =>  SNMP_VERSION_1,  # SNMP version
   }, $class;

   # Parse the passed arguments 

   my @transport = qw(
      -dstaddr -dstport -hostname -localaddr -localport -maxmsgsize
      -mtu -port -retries -srcaddr -srcport -timeout 
   );
   
   foreach (keys %argv) {

      if (/^-?debug$/i) {
         $this->debug(delete($argv{$_}));
      } elsif (/^-?nonblocking$/i) {
         $this->{_nonblocking} = (delete($argv{$_})) ? TRUE : FALSE;
      } elsif (/^-?translate$/i) {
         $this->translate(delete($argv{$_}));
      } elsif (/^-?version$/i) {
         $this->_version($argv{$_});
      } else {
         # Pull out arguments associated with the Transport Layer
         my $key   = $_;
         my @match = grep(/^-?\Q$key\E$/i, @transport);
         if (@match == 1) {
            push(@{$this->{_transport_argv}}, $match[0], delete($argv{$key}));
         }
      }

      if (defined($this->{_error})) {
         $this->_object_type_count;
         return wantarray ? (undef, $this->{_error}) : undef;
      }

   }

   # Create a Security Model object

   ($this->{_security}, $this->{_error}) = Net::SNMP::Security->new(%argv); 
   if (!defined($this->{_security})) {
      $this->_object_type_count;
      return wantarray ? (undef, $this->{_error}) : undef;
   }
   $this->_error_clear;

   # We must validate the object type to prevent blocking and 
   # non-blocking object from existing at the same time.
 
   if (!defined($this->_object_type_validate)) {
      $this->_object_type_count;
      return wantarray ? (undef, $this->{_error}) : undef;
   }
     
   # Return the object and empty error message (in list context)
   wantarray ? ($this, '') : $this;
}

sub open
{
   my ($this) = @_;

   # Clear any previous errors
   $this->_error_clear;

   # Create a Transport Layer object
   ($this->{_transport}, $this->{_error}) = Net::SNMP::Transport::UDP->new(
      @{$this->{_transport_argv}}
   );

   if (!defined($this->{_transport})) {
      return $this->_error;
   }
   $this->_error_clear;

   # Keep a copy of the hostname 
   $this->{_hostname} = $this->{_transport}->dstname;

   # Perform SNMPv3 authoritative engine discovery
   $this->_discovery if ($this->version == SNMP_VERSION_3);

   $this->{_transport};
}

=head2 session() - create a new Net::SNMP object

   ($session, $error) = Net::SNMP->session(
                           [-hostname      => $hostname,] 
                           [-port          => $port,]
                           [-localaddr     => $localaddr,]
                           [-localport     => $localport,]
                           [-nonblocking   => $boolean,]
                           [-version       => $version,]
                           [-timeout       => $seconds,]
                           [-retries       => $count,]
                           [-maxmsgsize    => $octets,]
                           [-translate     => $translate,]
                           [-debug         => $debugmask,]
                           [-community     => $community,]   # v1/v2c  
                           [-username      => $username,]    # v3  
                           [-authkey       => $authkey,]     # v3  
                           [-authpassword  => $authpasswd,]  # v3  
                           [-authprotocol  => $protocol,]    # v3  
                           [-privkey       => $privkey,]     # v3  
                           [-privpassword  => $privpasswd,]  # v3  
                        );

This is the constructor for Net::SNMP objects.  In scalar context, a
reference to a new Net::SNMP object is returned if the creation of the object
is successful.  In list context, a reference to a new Net::SNMP object and an 
empty error message string is returned.  If a failure occurs, the object 
reference is returned as the undefined value.  The error string may be used 
to determine the cause of the error.

Most of the named arguments passed to the constructor define basic attributes
for the object and are not modifiable after the object has been created.  The
B<-timeout>, B<-retries>, B<-maxmsgsize>, B<-translate>, and B<-debug>
arguments are modifiable using an accessor method.  See their corresponding 
method definitions for a complete description of their usage, default values, 
and valid ranges.

=over

=item Transport Layer Arguments

The Net::SNMP module uses UDP/IP as the Transport Layer to pass SNMP messages
between the local and remote devices.  The destination device can be specified
using the B<-hostname> argument.  The B<-hostname> argument accepts either
an IP network hostname or an IP address in dotted notation.  This argument 
is optional and defaults to "localhost".  The destination UPD port number can
be specified using the B<-port> argument.  This argument is also optional and
defaults to 161, which is the port number on which devices using default 
values expect to receive SNMP request messages.  The B<-port> argument will 
need to be specified for remote devices expecting to receive SNMP 
notifications since these device typically default to port 162.

By default, the source IP address and port number are assigned dynamically by 
the local device on which the Net::SNMP module is being used.  This dynamic 
assignment can be overridden by using the B<-localaddr> and B<-localport> 
arguments.  These values default to I<INADDR_ANY> (typically 0.0.0.0) and 0 
respectively.  The B<-localaddr> argument will accept either an IP network 
hostname or an IP address in dotted notation.  If a hostname is specified, the 
resolved IP address must be a valid address on the local device. 

=item Security Model Arguments

The B<-version> argument controls which other arguments are expected or 
required by the C<session()> constructor.  The Net::SNMP module supports 
SNMPv1, SNMPv2c, and SNMPv3.  The module defaults to SNMPv1 if no B<-version>
argument is specified.  The B<-version> argument expects either a digit (i.e. 
'1', '2', or '3') or a string specifying the version (i.e. 'snmpv1', 
'snmpv2c', or 'snmpv3') to define the SNMP version. 

The Security Model used by the Net::SNMP object is based on the SNMP version
associated with the object.  If the SNMP version is SNMPv1 or SNMPv2c a
Community-based Security Model will be used, while the User-based Security
Model (USM) will be used if the version is SNMPv3.  

=over

=item Community-based Security Model Argument 

If the Security Model is Community-based, the only argument available is the
B<-community> argument.  This argument expects a string that is to be used as
the SNMP community name.  By default the community name is set to 'public' 
if the argument is not present.

=item User-based Security Arguments 

The User-based Security Model used by SNMPv3 requires that a securityName be 
specified using the B<-username> argument.  The creation of a Net::SNMP
object with the version set to SNMPv3 will fail if the B<-username> argument
is not present.  The B<-username> argument expects a string 1 to 32 octets
in length.

The SNMPv3 User-based Security model (USM) allows different levels of security
which address authentication and privacy concerns.  A SNMPv3 Net::SNMP object
will derive the security level (securityLevel) based on which of the following 
arguments are specified.

By default a securityLevel of 'noAuthNoPriv' is assumed.  If the B<-authkey> 
or B<-authpassword> arguments are specified, the securityLevel becomes 
'authNoPriv'.  The B<-authpassword> argument expects a string which is 1 to 
32 bytes in length.  Optionally, the B<-authkey> argument can be used so that 
a plain text password does not have to be specified in a script.  The 
B<-authkey> argument expects a hexadecimal string produced by localizing the 
password with the authoritativeEngineID for the specific destination device.  
The C<snmpkey> utility included with the distribution can be used to create 
the hexadecimal string (see L<snmpkey>). 

Two different hash algorithms are defined by SNMPv3 which can be used by the 
Security Model for authentication.  These algorithms are MD5 (RFC 1321) and 
SHA-1 (NIST FIPS PUB 180).  The default algorithm used by the module is MD5.
This behavior can be changed by using the B<-authprotocol> argument.  This 
argument expects either the string 'md5' or 'sha1' to be passed to modify the 
hash algorithm.  

By specifying the arguments B<-privkey> or B<-privpassword> the securityLevel
associated with the object becomes 'authPriv'.  According to SNMPv3, privacy 
requires the use of authentication.  Therefore, if either of these two 
arguments are present and the B<-authkey> or B<-authpassword> arguments are 
missing, the creation of the object fails.  The B<-privkey> and 
B<-privpassword> arguments expect the same input as the B<-authkey> and 
B<-authpassword> arguments respectively.

=back

=back

=cut

sub session 
{
   my $class = shift;

   my ($this, $error) = $class->new(@_);

   if (defined($this)) {
      if (!defined($this->open)) {
         return wantarray ? (undef, $this->error) : undef;
      }
   }

   wantarray ? ($this, $error) : $this;
}

sub manager
{
   shift->session(@_);
}

=head2 close() - clear the Transport Layer associated with the object

   $session->close; 

This method clears the UDP Transport Layer and any errors associated with 
the object.  Once closed, the Net::SNMP object can no longer be used to 
send or receive SNMP messages.

=cut

sub close
{
   $_[0]->_error_clear;
   $_[0]->{_pdu}       = undef;
   $_[0]->{_transport} = undef;
}

=head2 snmp_dispatcher() - enter the non-blocking object event loop

   $session->snmp_dispatcher();

This method enters the event loop associated with non-blocking Net::SNMP
objects.  The method exits when all queued SNMP messages have received a
response or have timed out at the Transport Layer. This method is also 
exported as the stand alone function C<snmp_dispatcher()> by default 
(see L<"EXPORTS">).

=cut

sub snmp_dispatcher()
{
   $DISPATCHER->activate;
}

sub snmp_event_loop()
{
   snmp_dispatcher;
}

sub snmp_dispatch_once()
{
   $DISPATCHER->one_event;
}

=head2 get_request() - send a SNMP get-request to the remote agent

   $result = $session->get_request(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          -varbindlist      => \@oids,
                       );

This method performs a SNMP get-request query to gather data from the remote
agent on the host associated with the Net::SNMP object.  The message is built
using the list of OBJECT IDENTIFIERs in dotted notation passed to the method
as an array reference using the B<-varbindlist> argument.  Each OBJECT 
IDENTIFER is placed into a single SNMP GetRequest-PDU in the same order that 
it held in the original list.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no 
error has occurred.  In either mode, the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=cut

sub get_request
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}

=head2 get_next_request() - send a SNMP get-next-request to the remote agent

   $result = $session->get_next_request(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          -varbindlist      => \@oids,
                       );

This method performs a SNMP get-next-request query to gather data from the 
remote agent on the host associated with the Net::SNMP object.  The message 
is built using the list of OBJECT IDENTIFIERs in dotted notation passed to the 
method as an array reference using the B<-varbindlist> argument.  Each OBJECT 
IDENTIFER is placed into a single SNMP GetNextRequest-PDU in the same order 
that it held in the original list.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no 
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=cut

sub get_next_request
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_next_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}

=head2 set_request() - send a SNMP set-request to the remote agent

   $result = $session->set_request(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          -varbindlist      => \@oid_value,
                       );

This method is used to modify data on the remote agent that is associated
with the Net::SNMP object using a SNMP set-request.  The message is built 
using a list of values consisting of groups of an OBJECT IDENTIFIER, an object 
type, and the actual value to be set.  This list is passed to the method as 
an array reference using the B<-varbindlist> argument.  The OBJECT IDENTIFIERs 
in each trio are to be in dotted notation.  The object type is a byte 
corresponding to the ASN.1 type of value that is to be set.  Each of the 
supported ASN.1 types have been defined and are exported by the package by 
default (see L<"EXPORTS">). 

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

=cut

sub set_request
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_set_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}

=head2 trap() - send a SNMP trap to the remote manager

   $result = $session->trap(
                          [-delay           => $seconds,]   # non-blocking 
                          [-enterprise      => $oid,]
                          [-agentaddr       => $ipaddress,]
                          [-generictrap     => $generic,]
                          [-specifictrap    => $specific,]
                          [-timestamp       => $timeticks,]
                          -varbindlist      => \@oid_value,
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
the host on which the script is running or the local address specified by the
B<-localaddr> option.  The agent-addr is expected to be an IpAddress in 
dotted notation.

=item *

The default value for the B<-generictrap> type is 6 which corresponds to 
"enterpriseSpecific".  The generic-trap types are defined and can be exported
upon request (see L<"EXPORTS">).

=item *

The default value for the B<-specifictrap> type is 0.  No pre-defined values
are available for specific-trap types.

=item *

The default value for the trap B<-timestamp> is the "uptime" of the script.  
The "uptime" of the script is the number of hundredths of seconds that have 
elapsed since the script began running.  The time-stamp is expected to be a 
TimeTicks number in hundredths of seconds.

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

A true value is returned when the method is successful. The undefined value 
is returned when a failure has occurred.  The C<error()> method can be used to
determine the cause of the failure. Since there are no acknowledgements for 
Trap-PDUs, there is no way to determine if the remote host actually received
the trap.  

B<NOTE:> When the object is in non-blocking mode, the trap is not sent until 
the event loop is entered and no callback is ever executed.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv1.

=cut

sub trap
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -delay
                                          -enterprise
                                          -agentaddr
                                          -generictrap
                                          -specifictrap
                                          -timestamp
                                          -varbindlist  )], \@_, \@argv)))
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_trap(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;

   defined($this->{_error}) ? $this->_error : TRUE;
}

=head2 get_bulk_request() - send a get-bulk-request to the remote agent

   $result = $session->get_bulk_request(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          [-nonrepeaters    => $nonrep,]
                          [-maxrepetitions  => $maxrep,]
                          -varbindlist      => \@oids,
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
SNMPv2c or SNMPv3.

=cut

sub get_bulk_request
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname
                                          -nonrepeaters 
                                          -maxrepetitions 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_get_bulk_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}

=head2 inform_request() - send an inform-request to the remote manager

   $result = $session->inform_request(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          -varbindlist      => \@oid_value,
                       );

This method is used to provide management information to the remote manager
associated with the Net::SNMP object using an inform-request.  The message is 
built using a list of values consisting of groups of an OBJECT IDENTIFIER, 
an object type, and the actual value to be identified.  This list is passed 
to the method as an array reference using the B<-varbindlist> argument.  The 
OBJECT IDENTIFIERs in each trio are to be in dotted notation.  The object type 
is a byte corresponding to the ASN.1 type of value that is to be identified.  
Each of the supported ASN.1 types have been defined and are exported by the 
package by default (see L<"EXPORTS">). 

The first two variable-bindings fields in the inform-request are specified
by SNMPv2 and should be:

=over

=item *

sysUpTime.0 - ('1.3.6.1.2.1.1.3.0', TIMETICKS, $timeticks) 

=item *

snmpTrapOID.0 - ('1.3.6.1.6.3.1.1.4.1.0', OBJECT_IDENTIFIER, $oid)

=back

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv2c or SNMPv3.

=cut

sub inform_request
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -varbindlist     )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_inform_request(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;
}

=head2 snmpv2_trap() - send a snmpV2-trap to the remote manager

   $result = $session->snmpv2_trap(
                          [-delay           => $seconds,]   # non-blocking 
                          -varbindlist      => \@oid_value,
                       );

This method sends a snmpV2-trap to the remote manager associated with the 
Net::SNMP object.  The message is built using a list of values consisting of 
groups of an OBJECT IDENTIFIER, an object type, and the actual value to be 
identified.  This list is passed to the method as an array reference using the 
B<-varbindlist> argument.  The OBJECT IDENTIFIERs in each trio are to be in 
dotted notation.  The object type is a byte corresponding to the ASN.1 type 
of value that is to be identified.  Each of the supported ASN.1 types have 
been defined and are exported by the package by default (see L<"EXPORTS">). 

The first two variable-bindings fields in the snmpV2-trap are specified by
SNMPv2 and should be:

=over

=item *

sysUpTime.0 - ('1.3.6.1.2.1.1.3.0', TIMETICKS, $timeticks)

=item *

snmpTrapOID.0 - ('1.3.6.1.6.3.1.1.4.1.0', OBJECT_IDENTIFIER, $oid)

=back

A true value is returned when the method is successful. The undefined value 
is returned when a failure has occurred.  The C<error()> method can be used 
to determine the cause of the failure. Since there are no acknowledgements for
SNMPv2-Trap-PDUs, there is no way to determine if the remote host actually 
received the snmpV2-trap.  

B<NOTE:> When the object is in non-blocking mode, the snmpV2-trap is not sent 
until the event loop is entered and no callback is ever executed.

B<NOTE:> This method can only be used when the version of the object is set to
SNMPv2c.  SNMPv2-Trap-PDUs are supported by SNMPv3, but require the sender of
the message to be an authoritative SNMP engine which is not currently supported
by the Net::SNMP module.

=cut

sub snmpv2_trap
{
   my $this = shift;

   $this->_error_clear;

   my @argv;

   if (!defined($this->_prepare_argv([qw( -delay
                                          -varbindlist )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   if (!defined($this->{_pdu}->prepare_snmpv2_trap(@argv))) {
      return $this->_error($this->{_pdu}->error);
   }

   $this->_send_pdu;

   defined($this->{_error}) ? $this->_error : TRUE;
}

=head2 get_table() - retrieve a table from the remote agent

   $result = $session->get_table(
                          [-callback        => sub {},]     # non-blocking
                          [-delay           => $seconds,]   # non-blocking 
                          [-contextengineid => $engine_id,] # v3 
                          [-contextname     => $name,]      # v3
                          -baseoid          => $oid,
                       );

This method performs repeated SNMP get-next-request or get-bulk-request 
(when using SNMPv2c or SNMPv3) queries to gather data from the remote agent 
on the host associated with the Net::SNMP object.  The first message sent 
is built using the OBJECT IDENTIFIER in dotted notation passed to the method 
by the B<-baseoid> argument.   Repeated SNMP requests are issued until the 
OBJECT IDENTIFER in the response is no longer a child of the base OBJECT 
IDENTIFIER.

A reference to a hash is returned in blocking mode which contains the contents
of the VarBindList.  In non-blocking mode, a true value is returned when no
error has occurred.  In either mode the undefined value is returned when an
error has occurred.  The C<error()> method may be used to determine the cause
of the failure.

B<WARNING:> Results from this method can become very large if the base
OBJECT IDENTIFIER is close to the root of the SNMP MIB tree.

=cut

sub GET_TABLE_MAX_REPETITIONS() { 25 }  # Constant for get_table()

sub get_table
{
   my $this = shift;

   $this->_error_clear; 

   my @argv;

   # Validate the passed arguments.  For backwards compatiblity
   # see if the first argument is an OBJECT IDENTIFIER and then
   # act accordingly.

   if ((@_) && ($_[0] =~ /^\.?\d+\.\d+(?:\d+)*/)) {
      unshift(@_, '-baseoid');
   }

   if (!defined($this->_prepare_argv([qw( -callback
                                          -delay
                                          -contextengineid
                                          -contextname 
                                          -baseoid         )], \@_, \@argv))) 
   {
      return $this->_error;
   }

   if ($argv[0] !~ /^\.?\d+\.\d+(?:\d+)*/) {
      return $this->_error(
         'Expected base OBJECT IDENTIFIER in dotted notation'
      );
   }

   # Create a new PDU
   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   # Create table of values that need passed along with the
   # callbacks.  This just prevents a big argument list.

   my %argv = (
      'base_oid'   => $argv[0], 
      'callback'   => $this->_callback_closure,
      'repeat_cnt' => 0,
      'table'      => undef,
   );

   # Override the callback now that we have stored it
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
         $this->_get_table_cb(\%argv); 
      }
   );

   # Create a get-next-request or get-bulk-request PDU depending
   # on the SNMP version.

   if ($this->version == SNMP_VERSION_1) {
      if (!defined($this->{_pdu}->prepare_get_next_request([$argv[0]]))) {
         return $this->_error($this->{_pdu}->error);
      }
   } else {
      if (!defined(
            $this->{_pdu}->prepare_get_bulk_request(
                0, GET_TABLE_MAX_REPETITIONS, [$argv[0]]
            )
         )) 
      {
         return $this->_error($this->{_pdu}->error);
      }
   }

   $this->_send_pdu;
}

=head2 version() - get the SNMP version from the object

   $rfc_version = $session->version;

This method returns the current value for the SNMP version associated with
the object.  The returned value is the corresponding version number defined by
the RFCs for the protocol version field (i.e. SNMPv1 == 0, SNMPv2c == 1, and 
SNMPv3 == 3).  The RFC versions are defined as constant by the module and can 
be exported by request (see L<"EXPORTS">). 

=cut

sub version
{
   return $_[0]->_error('SNMP version is not modifiable') if (@_ == 2);

   $_[0]->{_version}; 
}

=head2 error() - get the current error message from the object

   $error_message = $session->error;

This method returns a text string explaining the reason for the last error.
An empty string is returned if no error has occurred.

=cut

sub error
{
   $_[0]->{_error} || '';
}

=head2 hostname() - get the hostname associated with the object

   $hostname = $session->hostname;

This method returns the hostname string that is associated with the object 
as it was passed to the C<session()> constructor.

=cut

sub hostname
{
   $_[0]->{_hostname};
}

=head2 error_status() - get the current SNMP error-status from the object

   $error_status = $session->error_status;

This method returns the numeric value of the error-status contained in the 
last SNMP GetResponse-PDU received by the object.

=cut

sub error_status
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->error_status : 0;
}

=head2 error_index() - get the current SNMP error-index from the object

   $error_index = $session->error_index;

This method returns the numeric value of the error-index contained in the 
last SNMP GetResponse-PDU received by the object.

=cut

sub error_index
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->error_index : 0;
}

=head2 var_bind_list() - get the hash reference to the last SNMP response

   $response = $session->var_bind_list;

This method returns a hash reference created using the ObjectName and the 
ObjectSyntax pairs in the VarBindList of the last SNMP GetResponse-PDU 
received by the object.  The keys of the hash consist of the OBJECT 
IDENTIFIERs in dotted notation corresponding to each ObjectName in the 
VarBindList.  If any of the OBJECT IDENTIFIERs passed to the request method 
began with a leading dot, all of the OBJECT IDENTIFIER hash keys will be 
prefixed with a leading dot.  The value of each hash entry is set equal to 
the value of the corresponding ObjectSyntax.  The undefined value is returned
if there has been a failure and the C<error()> method may be used to determine
the reason.

=cut

sub var_bind_list
{
   defined($_[0]->{_pdu}) ? $_[0]->{_pdu}->var_bind_list : undef;
}

=head2 timeout() - set or get the current timeout period for the object 

   $seconds = $session->timeout([$seconds]);

This method returns the current value for the Transport Layer timeout for 
the Net::SNMP object.  This value is the number of seconds that the object 
will wait for a response from the agent on the remote host.  The default 
timeout is 5.0 seconds.

If a parameter is specified, the timeout for the object is set to the provided
value if it falls within the range 1.0 to 60.0 seconds.  The undefined value
is returned upon an error and the C<error()> method may be used to determine
the cause.

=cut

sub timeout
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Layer defined');
   }

   my $timeout = $this->{_transport}->timeout(@_);

   defined($timeout) ? $timeout : $this->_error($this->{_transport}->error);
}

=head2 retries() - set or get the current retry count for the object

   $count = $session->retries([$count]);

This method returns the current value for the number of times to retry
sending a SNMP message to the remote host.  The default number of retries
is 1.

If a parameter is specified, the number of retries for the object is set to
the provided value if it falls within the range 0 to 20. The undefined value
is returned upon an error and the C<error()> method may be used to determine 
the cause.

=cut

sub retries
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Layer defined');
   }

   my $retries = $this->{_transport}->retries(@_);

   defined($retries) ? $retries : $this->_error($this->{_transport}->error);
}

=head2 max_msg_size() - set or get the current maxMsgSize for the object

   $octets = $session->max_msg_size([$octets]);

This method returns the current value for the maximum message size 
(maxMsgSize) for the Net::SNMP object.  This value is the largest message size
in octets that can be prepared or processed by the object.  The default 
maxMsgSize is 1472 octets.

If a parameter is specified, the maxMsgSize is set to the provided
value if it falls within the range 484 to 2147483647 octets.  The undefined 
value is returned upon an error and the C<error()> method may be used to 
determine the cause.

B<NOTE:> When using SNMPv3, the maxMsgSize is actually contained in the SNMP
message (as msgMaxSize).  If the value received from a remote device is less 
than the current maxMsgSize, the size is automatically adjusted to be the 
lower value.

=cut

sub max_msg_size
{
   my $this = shift;

   if (!defined($this->{_transport})) {
      return $this->_error('No Transport Layer defined');
   }

   my $max_size = $this->{_transport}->max_msg_size(@_);

   defined($max_size) ? $max_size : $this->_error($this->{_transport}->error);
}

sub mtu
{
   shift->max_msg_size(@_);
}

=head2 translate() - enable or disable the translation mode for the object

   $mask = $session->translate([ 
                        $mode |
                        [ # Perl anonymous ARRAY reference 
                           ['-all'            => $mode0,]
                           ['-none'           => $mode1,]
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

OCTET STRINGs and Opaques containing non-printable ASCII characters are 
converted into a hexadecimal representation prefixed with "0x".  B<NOTE:>  
The following ASCII control characters are considered to be printable by
the module:  NUL(0x00), HT(0x09), LF(0x0A), FF(0x0C), and CR(0x0D). 

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

Counter64, Counter, Gauge, and TimeTick values that have been incorrectly 
encoded as signed negative values are returned as unsigned values.

=back

The C<translate()> method can be invoked with two different types of arguments.

If the argument passed is any Perl variable type except an array reference,
the translation mode for all ASN.1 types is set to either enabled or disabled, 
depending on the value of the passed parameter.  Any value that Perl would 
treat as a true value will set the mode to be enabled for all types, while a 
false value will disable translation for all types.

A reference to an array can be passed to the C<translate()> method in order to
define the translation mode on a per ASN.1 type basis.  The array is expected
to contain a list of named argument pairs for each ASN.1 type that is to
be modified.  The arguments in the list are applied in the order that they
are passed in via the array.  Arguments at the end of the list supercede 
those passed earlier in the list.  The argument "-all" can be used to specify
that the mode is to apply to all ASN.1 types.  Only the arguments for the 
ASN.1 types that are to be modified need to be included in the list.

The C<translate()> method returns a bit mask indicating which ASN.1 types
are to be translated.  Definitions of the bit to ASN.1 type mappings can be
exported using the I<:translate> tag (see L<"EXPORTS">).  The undefined value 
is returned upon an error and the C<error()> method may be used to determine 
the cause.

=cut

sub translate
{
   if (@_ == 2) {

      if (ref($_[1]) ne 'ARRAY') {

         # Behave like we did before, do (not) translate everything
         $_[0]->_translate_mask($_[1], TRANSLATE_ALL);

      } else {

         # Allow the user to turn off and on specific translations.  An
         # array is used so the order of the arguments controls how the
         # mask is defined.

         my @argv = @{$_[1]};

         while (defined($_ = shift(@argv))) {
            if (/^-?all$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_ALL);
            } elsif (/^-?none$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_NONE);
            } elsif (/^-?octet_?string$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_OCTET_STRING);
            } elsif (/^-?null$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_NULL);
            } elsif (/^-?timeticks$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_TIMETICKS);
            } elsif (/^-?opaque$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_OPAQUE);
            } elsif (/^-?nosuchobject$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_NOSUCHOBJECT);
            } elsif (/^-?nosuchinstance$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_NOSUCHINSTANCE);
            } elsif (/^-?endofmibview$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_ENDOFMIBVIEW);
            } elsif (/^-?unsigned$/i) {
               $_[0]->_translate_mask(shift(@argv), TRANSLATE_UNSIGNED);
            } else {
               return $_[0]->_error("Invalid translate argument '%s'", $_);
            }
         }

      }

      DEBUG_INFO("translate = 0x%02x", $_[0]->{_translate});
   }

   $_[0]->{_translate};
}

=head2 debug() - set or get the debug mode for the module 

   $mask = $session->debug([$mask]);

This method is used to enable or disable debugging for the Net::SNMP module. 
Debugging can be enabled on a per component level as defined by a bit mask
passed to the C<debug()> method.  The bit mask is broken up as follows:

=over

=item * 

0x02 - Message or PDU encoding and decoding 

=item * 

0x04 - Transport Layer 

=item * 

0x08 - Dispatcher 

=item * 

0x10 - Message Processing  

=item * 

0x20 - Security

=back

Symbols representing these bit mask values are defined by the module and can
be exported using the I<:debug> tag (see L<"EXPORTS">).  If a non-numeric
value is passed to the C<debug()> method, it is evaluated in boolean context.
Debugging for all of the components is then enabled or disabled based on the
resulting truth value.

The current debugging mask is returned by the method.  Debugging can also be
enabled using the stand alone function C<snmp_debug()>. This function can be
exported by request (see L<"EXPORTS">). 

=cut

sub debug
{
   if (@_ == 2) {

      $DEBUG = ($_[1] =~ /^\d+$/) ? $_[1] : ($_[1]) ? DEBUG_ALL : DEBUG_NONE;

      eval { Net::SNMP::Message->debug($DEBUG & DEBUG_MESSAGE);              }; 
      eval { Net::SNMP::PDU->debug($DEBUG & DEBUG_MESSAGE);                  };
      eval { Net::SNMP::Transport::UDP->debug($DEBUG & DEBUG_TRANSPORT);     }; 
      eval { Net::SNMP::Dispatcher->debug($DEBUG & DEBUG_DISPATCHER);        };
      eval { Net::SNMP::MessageProcessing->debug($DEBUG & DEBUG_PROCESSING); }; 
      eval { Net::SNMP::Security->debug($DEBUG & DEBUG_SECURITY);            };
      eval { Net::SNMP::Security::Community->debug($DEBUG & DEBUG_SECURITY); }; 
      eval { Net::SNMP::Security::USM->debug($DEBUG & DEBUG_SECURITY);       }; 

   }

   $DEBUG;
}

sub snmp_debug($)
{
   debug(undef, $_[0]);
}

=head1 FUNCTIONS

=head2 oid_base_match() - determine if an OID has a specified OID base 

   $value = oid_base_match($base_oid, $oid);

This function takes two OBJECT IDENTIFIERs in dotted notation and returns a
true value (i.e. 0x1) if the second OBJECT IDENTIFIER is equal to or is a 
child of the first OBJECT IDENTIFIER in the SNMP Management Information Base 
(MIB).  This function can be used in conjunction with the C<get-next-request()>
or C<get-bulk-request()> methods to determine when a OBJECT IDENTIFIER in the 
GetResponse-PDU is no longer in the desired MIB tree branch.

=cut

sub oid_base_match($$)
{
   my ($base, $oid) = @_;

   $base || return FALSE;
   $oid  || return FALSE;

   $base =~ s/^\.//o;
   $oid  =~ s/^\.//o;

   $base = pack('N*', split('\.', $base));
   $oid  = pack('N*', split('\.', $oid));

   (substr($oid, 0, length($base)) eq $base) ? TRUE : FALSE;
}

sub oid_context_match($$)
{
   oid_base_match($_[0], $_[1]);
}

=head2 oid_lex_sort() - sort a list of OBJECT IDENTIFIERs lexicographically

   @sorted_oids = oid_lex_sort(@oids);

This function takes a list of OBJECT IDENTIFIERs in dotted notation and returns
the listed sorted in lexicographical order.

=cut

sub oid_lex_sort(@)
{
   return @_ unless (@_ > 1);

   map  { $_->[0] } 
   sort { $a->[1] cmp $b->[1] } 
   map  {
      my $oid = $_; 
      $oid =~ s/^\.//o;
      [$_, pack('N*', split('\.', $oid))]
   } @_;
}

=head2 ticks_to_time() - convert TimeTicks to formatted time

   $time = ticks_to_time($timeticks);

This function takes an ASN.1 TimeTicks value and returns a string representing
the time defined by the value.  The TimeTicks value is expected to be a 
non-negative integer value representing the time in hundredths of a second 
since some epoch.  The returned string will display the time in days, hours, 
and seconds format according to the value of the TimeTicks argument.

=cut

sub ticks_to_time($)
{
   asn1_ticks_to_time($_[0]);
}

sub VERSION
{
   # Provide our own VERSION method so that the version returns 
   # a dotted string instead of a v-string.

   my $version = eval { sprintf('%vd', shift->UNIVERSAL::VERSION(@_)); };

   if ($@) {
      $_ = $@;
      s/at(.*)/sprintf("at %s line %s\n", (caller(0))[1], (caller(0))[2])/es;
      die $_;
   } 

   $version;
}

sub DESTROY
{
   # We decrement the object type count when the object goes out of
   # existance.  We assume that _object_type_count() was called for
   # every creation or else we die.

   if ($_[0]->{_nonblocking}) {
      if (--$NONBLOCKING < 0) {
         die('FATAL: Invalid non-blocking object count');
      }
   } else {
      if (--$BLOCKING < 0) {
         die('FATAL: Invalid blocking object count');
      }
   }
}

# [private methods] ----------------------------------------------------------

sub _send_pdu
{
   my ($this) = @_;

   # Check to see if we are still in the process of discovering the
   # authoritative SNMP engine.  If we are, queue the PDU if we are 
   # running in non-blocking mode.

   if (($this->{_nonblocking}) && (!$this->{_security}->discovered)) {
      push(@{$this->{_discovery_queue}}, [$this->{_pdu}, $this->{_delay}]);
      return TRUE;
   }

   # Hand the PDU off to the Dispatcher
   $DISPATCHER->send_pdu($this->{_pdu}, $this->{_delay});

   # Activate the dispatcher if we are blocking
   snmp_dispatcher() unless ($this->{_nonblocking});
  
   # Return according to blocking mode 
   ($this->{_nonblocking}) ? TRUE : $this->var_bind_list;
}

sub _create_pdu
{
   my ($this) = @_;

   # Create the new PDU
   ($this->{_pdu}, $this->{_error}) = Net::SNMP::PDU->new(
      -version   => $this->version,
      -security  => $this->{_security},
      -transport => $this->{_transport},
      -translate => $this->{_translate},
      -callback  => $this->_callback_closure,
      defined($this->{_context_engine_id}) ? 
         (-contextengineid => $this->{_context_engine_id}) : (),
      defined($_[0]->{_context_name}) ?
         (-contextname     => $this->{_context_name})      : (),
   );

   if (!defined($this->{_pdu})) {
      return $this->_error;
   }
   $this->_error_clear;

   # Return the PDU
   $this->{_pdu};
}
    

sub _version
{
#  my ($this, $version) = @_;

   # Clear any previous error message
   $_[0]->_error_clear;

   # Allow the user some flexability
   my $supported = {
      '1'       => SNMP_VERSION_1,
      'v1'      => SNMP_VERSION_1,
      'snmpv1'  => SNMP_VERSION_1,
      '2c'      => SNMP_VERSION_2C,
      'v2c'     => SNMP_VERSION_2C,
      'snmpv2c' => SNMP_VERSION_2C,
      '3'       => SNMP_VERSION_3,
      'v3'      => SNMP_VERSION_3,
      'snmpv3'  => SNMP_VERSION_3
   };

   if (@_ == 2) {
      my @match = grep(/^\Q$_[1]/i, keys(%{$supported})); 
      if (@match != 1) {
         return $_[0]->_error('Unknown or invalid SNMP version [%s]', $_[1]);
      }
      $_[1] = $_[0]->{_version} = $supported->{$match[0]};
   }

   $_[0]->{_version};
}

sub _prepare_argv
{
#  my ($this, $allowed, $named, $unnamed) = @_;

   my $obj_args = {
      -callback        => \&_callback,          # non-blocking only
      -contextengineid => \&_context_engine_id, # v3 only
      -contextname     => \&_context_name,      # v3 only
      -delay           => \&_delay,             # non-blocking only
   };

   my %argv;

   # For backwards compatibility, check to see if the first 
   # argument is an OBJECT IDENTIFIER in dotted notation.  If it
   # is, assign it to the -varbindlist argument.

   if ((@{$_[2]}) && ($_[2]->[0] =~ /^\.?\d+\.\d+(?:\d+)*/)) {
      $argv{-varbindlist} = $_[2];
   } else {
      %argv = @{$_[2]};
   }

   # Go through the passed argument list and see if the argument is
   # allowed.  If it is, see if it applies to the object and has a 
   # matching method call or add it the the new argv list to be 
   # returned by this method.

   my %new_args;

   foreach my $key (keys(%argv)) {
      my @match = grep(/^-?\Q$key\E$/i, @{$_[1]});
      if (@match == 1) {
         if (exists($obj_args->{$match[0]})) {
            if (!defined($_[0]->${\$obj_args->{$match[0]}}($argv{$key}))) {
               return $_[0]->_error;
            }
         } else {
            $new_args{$match[0]} = $argv{$key};   
         }
      } else {
         return $_[0]->_error("Invalid argument '%s'", $key);
      }
   }

   # Create a new ordered unnamed argument list based on the allowed 
   # list passed, ignoring those that applied to the object.

   foreach (@{$_[1]}) {
      next if exists($obj_args->{$_});
      push(@{$_[3]}, exists($new_args{$_}) ? $new_args{$_} : undef);
   }

   $_[3];
}


sub _callback
{
   my ($this, $callback) = @_;
  
   # We validate the callback argument and then create an anonymous 
   # array where the first element is the subroutine reference and 
   # the second element is an array reference containing arguments 
   # to pass to the subroutine.

   if (!$this->{_nonblocking}) {
      return $this->_error('Callbacks are not applicable to blocking objects');
   }
 
   my @argv;

   if (!defined($callback)) {
      $_[0]->{_callback} = undef;
      return TRUE;
   } elsif ((ref($callback) eq 'ARRAY') && (ref($callback->[0]) eq 'CODE')) {
      @argv = @{$callback};
      $callback = shift(@argv);
   } elsif (ref($callback) ne 'CODE') {
      return $this->_error('Invalid callback format');
   }

   $this->{_callback} = [$callback, \@argv]; 
}

sub _callback_closure
{
   my ($this) = @_;

   # When a response message is received, the Dispatcher will create
   # a new PDU object and assign the callback to that object.  The
   # callback is then executed passing a reference to the PDU object 
   # as the first argument.  We use a closure to assign that passed 
   # reference to the Net:SNMP object and then invoke the user defined 
   # callback.

   if (!$this->{_nonblocking}) {

      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if ($this->{_pdu}->error);
      };

   } else {

      return undef unless defined ($this->{_callback});

      my $callback = $this->{_callback}->[0];
      my @argv = @{$this->{_callback}->[1]};

      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         $this->_error($this->{_pdu}->error) if ($this->{_pdu}->error);
         $callback->($this, @argv);
      };

   }

}

sub _context_engine_id
{
   my ($this, $context_engine_id) = @_;

   $this->_error_clear;

   if ($this->version != SNMP_VERSION_3) {
      return $this->_error('contextEngineID only supported in SNMPv3');
   }

   if (!defined($context_engine_id)) {
      $this->{_context_engine_id} = undef; 
      TRUE;
   } elsif ($context_engine_id =~ /^(?i:0x)?([a-fA-F0-9]{10,64})$/) {
      $this->{_context_engine_id} = pack('H*', length($1) % 2 ? '0'.$1 : $1);
   } else {
      $this->_error('Invalid contextEngineID format specified');
   }
}

sub _context_name
{
   my ($this, $context_name) = @_;

   $this->_error_clear;

   if ($this->version != SNMP_VERSION_3) {
      return $this->_error('contextName only supported in SNMPv3');
   }

   if (length($context_name) > 32) {
      return $this->_error(
         'Invalid contextName length [%d]', length($context_name)
      );
   }

   $this->{_context_name} = $context_name;
}

sub _delay
{
   my ($this, $delay) = @_;

   $this->_error_clear;

   if (!$this->{_nonblocking}) {
      return $this->_error('Delay not applicable to blocking objects');   
   }

   if ($delay !~ /^\d+(?:\.\d+)?$/) {
      return $_[0]->_error('Invalid delay value [%s]', $delay);
   }

   $this->{_delay} = $delay;
}

sub _object_type_validate
{
   my ($this) = @_;

   # Since both non-blocking and blocking objects use the same
   # Dispatcher instance, allowing both objects type to exist at
   # the same time would cause problems.  This method is called 
   # by the constructor to prevent this situation from happening.

   if (($this->{_nonblocking}) && ($BLOCKING)) {
      return $this->_error(
         'Cannot create non-blocking objects when blocking objects exist'
      );
   } elsif ((!$this->{_nonblocking}) && ($NONBLOCKING)) {
      return $this->_error(
         'Cannot create blocking objects when non-blocking objects exist'
      );
   }

   # Now we can bump up the object count
   $this->_object_type_count;
}

sub _object_type_count
{ 
   # This method must be called any time an object is created.  The
   # destructor will decrement this count.

   ($_[0]->{_nonblocking}) ? $NONBLOCKING++ : $BLOCKING++;
} 

sub _discovery
{
   my ($this) = @_;

   return TRUE if ($this->{_security}->discovered);

   # RFC 2274 - Section 4: "Discovery... ...may be accomplished by
   # generating a Request message with a securityLevel of noAuthNoPriv,
   # a msgUserName of "initial", a msgAuthoritativeEngineID value of
   # zero length, and the varBindList left empty."

   # Create a new PDU
   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   # Create the callback and assign it to the PDU
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         if ($this->{_pdu}->error) {
            $this->_error($this->{_pdu}->error . ' during discovery');
         }
         $this->_discovery_engine_id_cb; 
      }
   );

   # Prepare an empty get-request
   if (!defined($this->{_pdu}->prepare_get_request)) {
      return $this->_error($this->{_pdu}->error);
   }

   # Send the PDU
   $DISPATCHER->send_pdu($this->{_pdu}, 0);

   snmp_dispatcher() unless ($this->{_nonblocking});

   ($this->{_error}) ? $this->_error : TRUE;
}

sub _discovery_engine_id_cb
{
   my ($this) = @_;

   # "The response to this message will be a Report message containing 
   # the snmpEngineID of the authoritative SNMP engine...  ...with the 
   # usmStatsUnknownEngineIDs counter in the varBindList."  If another 
   # error is returned, we assume snmpEngineID discovery has failed.

   if ($this->{_error} !~ /usmStatsUnknownEngineIDs/) {

      # Discovery of the snmpEngineID has failed, clear the 
      # current PDU and the Transport Layer so no one can use 
      # this object to send messages.
 
      $this->{_pdu}       = undef;
      $this->{_transport} = undef;

      # Upcall any pending messages with the current error
      while ($_ = shift(@{$this->{_discovery_queue}})) {
         $_->[0]->error($this->{_error});
         $_->[0]->callback_execute;
      }

      return $this->_error;
   }

   # Clear the usmStatsUnknownEngineIDs error
   $this->_error_clear;

   # If the security model indicates that discovery is complete,
   # we send any pending messages and return success.  If discovery
   # is not complete, we probably need to synchronize with the
   # remote authoritative engine.

   if ($this->{_security}->discovered) {

      DEBUG_INFO('discovery complete');

      # Discovery is complete, send any pending messages
      while ($_ = shift(@{$this->{_discovery_queue}})) {
         $DISPATCHER->send_pdu(@{$_});
      }

      return TRUE;
   }

   # "If authenticated communication is required, then the discovery
   # process should also establish time synchronization with the
   # authoritative SNMP engine.  This may be accomplished by sending
   # an authenticated Request message..."

   # Create a new PDU
   if (!defined($this->_create_pdu)) {
      return $this->_error;
   }

   # Create the callback and assign it to the PDU
   $this->{_pdu}->callback(
      sub {
         $this->{_pdu} = $_[0];
         $this->_error_clear;
         if ($this->{_pdu}->error) {
            $this->_error($this->{_pdu}->error . ' during synchronization');
         }
         $this->_discovery_synchronization_cb;
      }
   );

   # Prepare an empty get-request
   if (!defined($this->{_pdu}->prepare_get_request)) {
      return $this->_error($this->{_pdu}->error);
   }

   # Send the PDU
   $DISPATCHER->send_pdu($this->{_pdu}, 0);

   snmp_dispatcher() unless ($this->{_nonblocking});

   ($this->{_error}) ? $this->_error : TRUE;
}

sub _discovery_synchronization_cb
{
   my ($this) = @_;

   # "The response... ...will be a Report message containing the up 
   # to date values of the authoritative SNMP engine's snmpEngineBoots 
   # and snmpEngineTime...  It also contains the usmStatsNotInTimeWindows
   # counter in the varBindList..."  If another error is returned, we 
   # assume that the synchronization has failed.

   if (($this->{_security}->discovered) &&
       ($this->{_error} =~ /usmStatsNotInTimeWindows/))
   {
      $this->_error_clear;
    
      DEBUG_INFO('discovery and synchronization complete');

      # Discovery is complete, send any pending messages
      while ($_ = shift(@{$this->{_discovery_queue}})) {
         $DISPATCHER->send_pdu(@{$_});
      }

      return TRUE;
   }

   # If we received the usmStatsNotInTimeWindows report or no error, but 
   # we are still not synchronized, provide a generic error message.

   if ((!$this->{_error}) || ($this->{_error} =~ /usmStatsNotInTimeWindows/)) {
      $this->_error_clear;
      $this->_error('Time synchronization failed during discovery');
   }

   DEBUG_INFO('synchronization failed');

   # Synchronization has failed, clear the current PDU and 
   # the Transport Layer so no one can use this object to 
   # send messages.

   $this->{_pdu}       = undef;
   $this->{_transport} = undef;

   # Upcall any pending messages with the current error
   while ($_ = shift(@{$this->{_discovery_queue}})) {
      $_->[0]->error($this->{_error});
      $_->[0]->callback_execute;
   }

   $this->_error;
}


sub _translate_mask
{
   my ($this, $enable, $mask) = @_;

   # Define the translate bitmask for the object based on the
   # passed truth value and mask.

   if (@_ != 3) {
      return $this->{_translate};
   }

   if ($enable) {
      $this->{_translate} |= $mask;  # Enable
   } else {
      $this->{_translate} &= ~$mask; # Disable
   }
}

sub _get_table_cb
{
   my ($this, $argv) = @_;

   # Use get-next-requests or get-bulk-requests until the response is
   # not a subtree of the base OBJECT IDENTIFIER.  Return the table only
   # if there are no errors other than a noSuchName(2) error since the
   # table could be at the end of the tree.  Also return the table when
   # the value of the OID equals endOfMibView(2) when using SNMPv2c.

   # Assign the "real" callback to the PDU 
   $this->{_pdu}->callback($argv->{callback});

   # Check to see if the var_bind_list is defined (was there an error?)

   if (defined(my $result = $this->var_bind_list)) {

      my @oids = oid_lex_sort(keys(%{$result}));
      my ($next_oid, $end_of_table) = (undef, FALSE);

      do {

         $next_oid = shift(@oids);

         # Add the entry to the table

         if (oid_base_match($argv->{base_oid}, $next_oid)) {

            if (!exists($argv->{table}->{$next_oid})) {
               $argv->{table}->{$next_oid} = $result->{$next_oid};
            } elsif (($result->{$next_oid} eq 'endOfMibView')      # translate
                     || (($result->{$next_oid} eq '')              # !translate
                        && ($this->error_status == ENDOFMIBVIEW)))
            {
               $end_of_table = TRUE;
            } else {
               $argv->{repeat_cnt}++;
            }

            # Check to make sure that the remote host does not respond
            # incorrectly causing the requests to loop forever.

            if ($argv->{repeat_cnt} > GET_TABLE_MAX_REPETITIONS) {
               $this->{_pdu}->var_bind_list(undef);
               $this->{_pdu}->error('Loop detected with table on remote host');
               return $this->{_pdu}->callback_execute;
            }

         } else {
            $end_of_table = TRUE;
         }

      } while (@oids);

      # Queue the next request if we are not at the end of the table.

      if (!$end_of_table) {
       
         # Create a new PDU
         if (!defined($this->_create_pdu)) {
            $this->{_pdu}->var_bind_list(undef);
            return $this->{_pdu}->callback_execute;
         }

         # Override the callback
         $this->{_pdu}->callback(
            sub {
               $this->{_pdu} = $_[0];
               $this->_error_clear;
               $this->_error($this->{_pdu}->error) if $this->{_pdu}->error;
               $this->_get_table_cb($argv);
            }
         );

         if ($this->version == SNMP_VERSION_1) {
            if (!defined(
                  $this->{_pdu}->prepare_get_next_request([$next_oid])
               )) 
            {
               $this->{_pdu}->var_bind_list(undef);
               return $this->{_pdu}->callback_execute;
            }
         } else {
            if (!defined(
                  $this->{_pdu}->prepare_get_bulk_request(
                     0, GET_TABLE_MAX_REPETITIONS, [$next_oid]
                  )
               ))
            {
               $this->{_pdu}->var_bind_list(undef);
               return $this->{_pdu}->callback_execute;
            }
         } 

         # Send the next PDU with no delay
         return $DISPATCHER->send_pdu($this->{_pdu}, 0) ? TRUE : $this->_error;
      }

      # Copy the table to the var_bind_list
      $this->{_pdu}->var_bind_list($argv->{table});

   }

   # Check for noSuchName(2) error
   if ($this->error_status == 2) {
      $this->{_pdu}->error(undef);
      $this->{_pdu}->var_bind_list($argv->{table});
   }

   if (!defined($argv->{table}) && (!$this->{_pdu}->error)) {
      $this->{_pdu}->error( 
         'Requested table is empty or does not exist'
      );
   }

   # Invoke the user defined callback.
   $this->{_pdu}->callback_execute;
}

sub _error
{
   my $this = shift;

   if (!defined($this->{_error})) {
      $this->{_error} = sprintf(shift(@_), @_);
      if ($this->debug) {
         printf("error: [%d] %s(): %s\n",
            (caller(0))[2], (caller(1))[3], $this->{_error}
         );
      }
   }

   return;
}

sub _error_clear
{
   $_[0]->{_error} = undef;
}

sub require_version
{
   # As of Exporter v5.562, the require_version() method does not
   # handle x.y.z version strings properly.  We provide our own 
   # method to handle our x.y.z version requirements.

   my ($this, $wanted) = @_;

   my $pkg = ref($this) || $this;

   if ($wanted =~ /(\d+)\.(\d{1,3})\.(\d{1,3})/) {
      $wanted = sprintf('%d.%03d%03d', $1, $2, $3);
   } elsif ($wanted =~ /(\d+)\.(\d+)/) {
      $wanted = sprintf('%d.%d', $1, $2);
   }

   my $version = eval { $pkg->UNIVERSAL::VERSION($wanted); };

   if ($@) {
      $_ = $@;
      s/at(.*)/sprintf("at %s line %s\n", (caller(2))[1], (caller(2))[2])/es;
      die $_;
   }
 
   $version;
}

sub DEBUG_INFO
{
   return unless $DEBUG;

   printf(
      sprintf('debug: [%d] %s(): ', (caller(0))[2], (caller(1))[3]) .
      shift(@_) .
      "\n",
      @_
   );

   $DEBUG;
}

# [documentation] ------------------------------------------------------------

=head1 EXPORTS

The Net::SNMP module uses the F<Exporter> module to export useful constants 
and subroutines.  These exportable symbols are defined below and follow the
rules and conventions of the F<Exporter> module (see L<Exporter>).

=over

=item Default

&snmp_dispatcher, INTEGER, INTEGER32, OCTET_STRING, OBJECT_IDENTIFIER, 
IPADDRESS, COUNTER, COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, 
OPAQUE, COUNTER64, NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW 

=item Exportable

&snmp_debug, &snmp_dispatcher, &oid_base_match, &oid_lex_sort, &ticks_to_time,
INTEGER, INTEGER32, OCTET_STRING, NULL, OBJECT_IDENTIFIER, SEQUENCE, IPADDRESS,
COUNTER, COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, OPAQUE, COUNTER64, 
NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW, GET_REQUEST, GET_NEXT_REQUEST, 
GET_RESPONSE, SET_REQUEST, TRAP, GET_BULK_REQUEST, INFORM_REQUEST, SNMPV2_TRAP,
DEBUG_ALL, DEBUG_NONE, DEBUG_MESSAGE, DEBUG_TRANSPORT, DEBUG_DISPATCHER, 
DEBUG_PROCESSING, DEBUG_SECURITY, COLD_START, WARM_START, LINK_DOWN, LINK_UP, 
AUTHENTICATION_FAILURE, EGP_NEIGHBOR_LOSS, ENTERPRISE_SPECIFIC, SNMP_VERSION_1,
SNMP_VERSION_2C, SNMP_VERSION_3, SNMP_PORT, SNMP_TRAP_PORT, TRANSLATE_NONE, 
TRANSLATE_OCTET_STRING, TRANSLATE_NULL, TRANSLATE_TIMETICKS, TRANSLATE_OPAQUE,
TRANSLATE_NOSUCHOBJECT, TRANSLATE_NOSUCHINSTANCE, TRANSLATE_ENDOFMIBVIEW, 
TRANSLATE_UNSIGNED, TRANSLATE_ALL

=item Tags

=over 

=item :asn1

INTEGER, INTEGER32, OCTET_STRING, NULL, OBJECT_IDENTIFIER, SEQUENCE, 
IPADDRESS, COUNTER, COUNTER32, GAUGE, GAUGE32, UNSIGNED32, TIMETICKS, OPAQUE, 
COUNTER64, NOSUCHOBJECT, NOSUCHINSTANCE, ENDOFMIBVIEW, GET_REQUEST, 
GET_NEXT_REQUEST, GET_RESPONSE, SET_REQUEST, TRAP, GET_BULK_REQUEST, 
INFORM_REQUEST, SNMPV2_TRAP

=item :debug

&snmp_debug, DEBUG_ALL, DEBUG_NONE, DEBUG_MESSAGE, DEBUG_TRANSPORT, 
DEBUG_DISPATCHER, DEBUG_PROCESSING, DEBUG_SECURITY

=item :generictrap

COLD_START, WARM_START, LINK_DOWN, LINK_UP, AUTHENTICATION_FAILURE,
EGP_NEIGHBOR_LOSS, ENTERPRISE_SPECIFIC

=item :snmp

&snmp_debug, &snmp_dispatcher, &oid_base_match, &oid_lex_sort, &ticks_to_time,
SNMP_VERSION_1, SNMP_VERSION_2C, SNMP_VERSION_3, SNMP_PORT, SNMP_TRAP_PORT 

=item :translate

TRANSLATE_NONE, TRANSLATE_OCTET_STRING, TRANSLATE_NULL, TRANSLATE_TIMETICKS,
TRANSLATE_OPAQUE, TRANSLATE_NOSUCHOBJECT, TRANSLATE_NOSUCHINSTANCE, 
TRANSLATE_ENDOFMIBVIEW, TRANSLATE_UNSIGNED, TRANSLATE_ALL

=item :ALL

All of the above exportable items.

=back

=back

=head1 EXAMPLES

=head2 1. Blocking SNMPv1 get-request for sysUpTime

This example gets the sysUpTime from a remote host.

   #! /usr/local/bin/perl

   use strict;

   use Net::SNMP;

   my ($session, $error) = Net::SNMP->session(
      -hostname  => shift || 'localhost',
      -community => shift || 'public',
      -port      => shift || 161 
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit 1;
   }

   my $sysUpTime = '1.3.6.1.2.1.1.3.0';

   my $result = $session->get_request(
      -varbindlist => [$sysUpTime]
   );

   if (!defined($result)) {
      printf("ERROR: %s.\n", $session->error);
      $session->close;
      exit 1;
   }

   printf("sysUpTime for host '%s' is %s\n",
      $session->hostname, $result->{$sysUpTime} 
   );

   $session->close;

   exit 0;

=head2 2. Blocking SNMPv3 set-request of sysContact

This example sets the sysContact information on the remote host to 
"Help Desk x911".  The named arguments passed to the C<session()> constructor
are for the demonstration of syntax only.  These parameters will need to be
set according to the SNMPv3 parameters of the remote host used by the script. 

   #! /usr/local/bin/perl

   use strict;

   use Net::SNMP;

   my ($session, $error) = Net::SNMP->session(
      -hostname     => 'myv3host.company.com',
      -version      => 'snmpv3',
      -username     => 'myv3Username',
      -authkey      => '0x05c7fbde31916f64da4d5b77156bdfa7',
      -authprotocol => 'md5',
      -privkey      => '0x93725fd3a02a48ce02df4e065a1c1746'
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit 1;
   }

   my $sysContact = '1.3.6.1.2.1.1.4.0';

   my $result = $session->set_request(
      -varbindlist => [$sysContact, OCTET_STRING, 'Help Desk x911']
   );

   if (!defined($result)) {
      printf("ERROR: %s.\n", $session->error);
      $session->close;
      exit 1;
   }

   printf("sysContact for host '%s' set to '%s'\n", 
      $session->hostname, $result->{$sysContact}
   );

   $session->close;

   exit 0;

=head2 3. Non-blocking SNMPv2c get-bulk-request for ifTable

This example gets the contents of the ifTable by sending get-bulk-requests
until the responses are no longer part of the ifTable.  The ifTable can also 
be retrieved using the C<get_table()> method. 

   #! /usr/local/bin/perl

   use strict;

   use Net::SNMP qw(:snmp);

   my ($session, $error) = Net::SNMP->session(
      -version     => 'snmpv2c',
      -nonblocking => 1,
      -hostname    => shift || 'localhost',
      -community   => shift || 'public',
      -port        => shift || 161 
   );

   if (!defined($session)) {
      printf("ERROR: %s.\n", $error);
      exit 1;
   }

   my $ifTable = '1.3.6.1.2.1.2.2';

   my $result = $session->get_bulk_request(
      -callback       => [\&table_cb, {}],
      -maxrepetitions => 10,
      -varbindlist    => [$ifTable]
   );

   if (!defined($result)) {
      printf("ERROR: %s.\n", $session->error);
      $session->close;
      exit 1;
   }

   snmp_dispatcher();

   $session->close;

   exit 0;

   sub table_cb
   {
      my ($session, $table) = @_;

      if (!defined($session->var_bind_list)) {

         printf("ERROR: %s\n", $session->error);   

      } else {

         # Loop through each of the OIDs in the response and assign
         # the key/value pairs to the anonymous hash that is passed
         # to the callback.  Make sure that we are still in the table
         # before assigning the key/values.

         my $next;

         foreach my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) {
            if (!oid_base_match($ifTable, $oid)) {
               $next = undef;
               last;
            }
            $next = $oid; 
            $table->{$oid} = $session->var_bind_list->{$oid};   
         }

         # If $next is defined we need to send another request 
         # to get more of the table.

         if (defined($next)) {

            $result = $session->get_bulk_request(
               -callback       => [\&table_cb, $table],
               -maxrepetitions => 10,
               -varbindlist    => [$next]
            ); 

            if (!defined($result)) {
               printf("ERROR: %s\n", $session->error);
            }

         } else {

            # We are no longer in the table, so print the results.

            foreach my $oid (oid_lex_sort(keys(%{$table}))) {
               printf("%s => %s\n", $oid, $table->{$oid});
            }

         }
      }
   }

=head2 4. Non-blocking SNMPv1 get-request for sysUpTime on multiple hosts

This example polls several hosts for their sysUpTime using non-blocking
objects and reports a warning if this value is less than the value from
the last poll.

   #! /usr/local/bin/perl

   use strict;

   use Net::SNMP qw(snmp_dispatcher ticks_to_time);

   # List of hosts to poll

   my @HOSTS = qw(1.1.1.1 1.1.1.2 localhost);

   # Poll interval (in seconds).  This value should be greater 
   # than the number of retries plus one, times the timeout value.

   my $INTERVAL  = 60;

   # Maximum number of polls, including the initial poll.

   my $MAX_POLLS = 10;

   my $sysUpTime = '1.3.6.1.2.1.1.3.0';

   # Create a session for each host and queue the first get-request.

   foreach my $host (@HOSTS) {

      my ($session, $error) = Net::SNMP->session(
         -hostname    => $host,
         -nonblocking => 0x1,   # Create non-blocking objects
         -translate   => [
            -timeticks => 0x0   # Turn off so sysUpTime is numeric
         ]  
      );
      if (!defined($session)) {
         printf("ERROR: %s.\n", $error);
         exit 1;
      }

      # Queue the get-request, passing references to variables that
      # will be used to store the last sysUpTime and the number of
      # polls that this session has performed. 

      my ($last_uptime, $num_polls) = (0, 0);

      $session->get_request(
          -varbindlist => [$sysUpTime],
          -callback    => [
             \&validate_sysUpTime_cb, \$last_uptime, \$num_polls
          ]
      );

   }

   # Define a reference point for all of the polls
   my $EPOC = time();

   # Enter the event loop
   snmp_dispatcher();

   exit 0;


   sub validate_sysUpTime_cb
   {
      my ($session, $last_uptime, $num_polls) = @_;
  
      if (!defined($session->var_bind_list)) {

         printf("%-15s  ERROR: %s\n", $session->hostname, $session->error);

      } else {
   
         # Validate the sysUpTime

         my $uptime = $session->var_bind_list->{$sysUpTime};

         if ($uptime < ${$last_uptime}) {
            printf("%-15s  WARNING: %s is less than %s\n",
               $session->hostname, 
               ticks_to_time($uptime), 
               ticks_to_time(${$last_uptime})
            );
         } else {
            printf("%-15s  Ok (%s)\n", 
               $session->hostname, ticks_to_time($uptime)
            );
         }

         # Store the new sysUpTime
         ${$last_uptime} = $uptime;

      }

      # Queue the next message if we have not reached $MAX_POLLS.  
      # Since we do not provide a -callback argument, the same 
      # callback and it's original arguments will be used.

      if (++${$num_polls} < $MAX_POLLS) {
         my $delay = (($INTERVAL * ${$num_polls}) + $EPOC) - time();
         $session->get_request(
            -delay       => ($delay >= 0) ? $delay : 0,
            -varbindlist => [$sysUpTime]
         );
      }

      $session->error_status;
   }

=head1 REQUIREMENTS

=over

=item *

The Net::SNMP module uses syntax that is not supported in versions of Perl 
earlier than v5.6.0. 

=item *

The non-core modules F<Crypt::DES>, F<Digest::MD5>, F<Digest::SHA1>, and 
F<Digest::HMAC> are required to support SNMPv3. 

=back

=head1 AUTHOR

David M. Town <dtown@cpan.org>

=head1 ACKNOWLEDGMENTS

The original concept for this module was based on F<SNMP_Session.pm> 
written by Simon Leinen <simon@switch.ch>.

The Abstract Syntax Notation One (ASN.1) encode and decode methods were 
derived by example from the CMU SNMP package whose copyright follows: 
Copyright (c) 1988, 1989, 1991, 1992 by Carnegie Mellon University.  
All rights reserved. 

=head1 COPYRIGHT

Copyright (c) 1998-2002 David M. Town.  All rights reserved.  This program 
is free software; you may redistribute it and/or modify it under the same
terms as Perl itself.

=cut

# ============================================================================
1; # [end Net::SNMP]
