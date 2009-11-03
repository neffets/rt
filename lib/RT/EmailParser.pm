# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2007 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}
package RT::EmailParser;

use strict;
use warnings;

use Email::Address;
use MIME::Entity;
use MIME::Head;
use MIME::Parser;
use File::Temp qw/tempdir/;

=head1 NAME

  RT::EmailParser - helper functions for parsing parts from incoming
  email messages

=head1 SYNOPSIS


=head1 description




=head1 METHODS

=head2 new

Returns a RT::EmailParser->new Object

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );
    return $self;
}

=head2 smart_parse_mime_entity_from_scalar Message => SCALAR_REF [, Decode => BOOL, Exact => BOOL ] }

Parse a message stored in a scalar from scalar_ref.

=cut

sub smart_parse_mime_entity_from_scalar {
    my $self = shift;
    my %args = ( message => undef, decode => 1, exact => 0, @_ );

    eval {
        my ( $fh, $temp_file );
        for ( 1 .. 10 ) {

            # on NFS and NTFS, it is possible that tempfile() conflicts
            # with other processes, causing a race condition. we try to
            # accommodate this by pausing and retrying.
            last
                if ( $fh, $temp_file ) = eval { File::Temp::tempfile( undef, UNLINK => 0 ) };
            sleep 1;
        }
        if ($fh) {

            #thank you, windows
            binmode $fh;
            $fh->autoflush(1);
            print $fh $args{'message'};
            close($fh);
            if ( -f $temp_file ) {

                # We have to trust the temp file's name -- untaint it
                $temp_file =~ /(.*)/;
                my $entity = $self->parse_mime_entity_from_file( $1, $args{'decode'}, $args{'exact'} );
                unlink($1);
                return $entity;
            }
        }
    };

    #If for some reason we weren't able to parse the message using a temp file
    # try it with a scalar
    if ( $@ || !$self->entity ) {
        return $self->parse_mime_entity_from_scalar( $args{'message'}, $args{'decode'}, $args{'exact'} );
    }

}

=head2 parse_mime_entity_from_stdin

Parse a message from standard input

=cut

sub parse_mime_entity_from_stdin {
    my $self = shift;
    return $self->parse_mime_entity_from_filehandle( \*STDIN, @_ );
}

=head2 parse_mime_entity_from_scalar  $message

Takes either a scalar or a reference to a scalar which contains a stringified MIME message.
Parses it.

Returns true if it wins.
Returns false if it loses.

=cut

sub parse_mime_entity_from_scalar {
    my $self = shift;
    return $self->_parse_mime_entity( shift, 'parse_data', @_ );
}

=head2 parse_mime_entity_from_filehandle *FH

Parses a mime entity from a filehandle passed in as an argument

=cut

sub parse_mime_entity_from_filehandle {
    my $self = shift;
    return $self->_parse_mime_entity( shift, 'parse', @_ );
}

=head2 parse_mime_entity_from_file 

Parses a mime entity from a filename passed in as an argument

=cut

sub parse_mime_entity_from_file {
    my $self = shift;
    return $self->_parse_mime_entity( shift, 'parse_open', @_ );
}

sub _parse_mime_entity {
    my $self        = shift;
    my $message     = shift;
    my $method      = shift;
    my $postprocess = ( @_ ? shift : 1 );
    my $exact       = shift;

    # Create a new parser object:
    my $parser = MIME::Parser->new();
    $self->_setup_mime_parser($parser);
    $parser->decode_bodies(0) if $exact;

    # TODO: XXX 3.0 we really need to wrap this in an eval { }
    unless ( $self->{'entity'} = $parser->$method($message) ) {
        Jifty->log->fatal("Couldn't parse MIME stream and extract the submessages");

        # Try again, this time without extracting nested messages
        $parser->extract_nested_messages(0);
        unless ( $self->{'entity'} = $parser->$method($message) ) {
            Jifty->log->fatal("couldn't parse MIME stream");
            return (undef);
        }
    }

    $self->_post_process_new_entity if $postprocess;

    return $self->{'entity'};
}

sub _decode_bodies {
    my $self = shift;
    return unless $self->{'entity'};

    my @parts = $self->{'entity'}->parts_DFS;
    $self->_decode_body($_) foreach @parts;
}

sub _decode_body {
    my $self   = shift;
    my $entity = shift;

    my $old = $entity->bodyhandle or return;
    return unless $old->is_encoded;

    require MIME::Decoder;
    my $encoding = $entity->head->mime_encoding;
    my $decoder  = new MIME::Decoder $encoding;
    unless ($decoder) {
        Jifty->log->error("Couldn't find decoder for '$encoding', switching to binary");
        $old->is_encoded(0);
        return;
    }

    require MIME::Body;

    # XXX: use InCore for now, but later must switch to files
    my $new = new MIME::Body::InCore;
    $new->binmode(1);
    $new->is_encoded(0);

    my $source      = $old->open('r') or die "couldn't open body: $!";
    my $destination = $new->open('w') or die "couldn't open body: $!";
    {
        local $@;
        eval { $decoder->decode( $source, $destination ) };
        Jifty->log->error($@) if $@;
    }
    $source->close      or die "can't close: $!";
    $destination->close or die "can't close: $!";

    $entity->bodyhandle($new);
}

=head2 _post_process_new_entity

cleans up and postprocesses a newly parsed MIME Entity

=cut

sub _post_process_new_entity {
    my $self = shift;

    #Now we've got a parsed mime object.

    # Unfold headers that are have embedded newlines
    #  Better do this before conversion or it will break
    #  with multiline encoded subject (RFC2047) (fsck.com #5594)
    $self->head->unfold;

    # try to convert text parts into utf-8 charset
    RT::I18N::set_mime_entity_to_encoding( $self->{'entity'}, 'utf-8' );
}

=head2 is_rtaddress ADDRESS

Takes a single parameter, an email address. 
Returns true if that address matches the C<RTAddressRegexp> config option.
Returns false, otherwise.


=cut

sub is_rt_address {
    my $self    = shift;
    my $address = shift;

    # Example: the following rule would tell RT not to Cc
    #   "tickets@noc.example.com"
    my $address_re = RT->config->get('rt_address_regexp');
    if ( defined $address_re && $address =~ /$address_re/i ) {
        return 1;
    }
    return undef;
}

=head2 cull_rt_addresses ARRAY

Takes a single argument, an array of email addresses.
Returns the same array with any is_rt_address()es weeded out.


=cut

sub cull_rt_addresses {
    my $self      = shift;
    my @addresses = (@_);
    my @addrlist;

    foreach my $addr (@addresses) {

        # We use the class instead of the instance
        # because sloppy code calls this method
        # without a $self
        push( @addrlist, $addr ) unless RT::EmailParser->is_rt_address($addr);
    }
    return (@addrlist);
}

# LookupExternalUserInfo is a site-definable method for synchronizing
# incoming users with an external data source.
#
# This routine takes a tuple of email and friendly_name
#   email is the user's email address, ususally taken from
#       an email message's From: header.
#   friendly_name is a freeform string, ususally taken from the "comment"
#       portion of an email message's From: header.
#
# If you define an AutoRejectRequest template, RT will use this
# template for the rejection message.

=head2 lookup_external_user_info

 LookupExternalUserInfo is a site-definable method for synchronizing
 incoming users with an external data source. 

 This routine takes a tuple of email and friendly_name
    email is the user's email address, ususally taken from
        an email message's From: header.
    friendly_name is a freeform string, ususally taken from the "comment" 
        portion of an email message's From: header.

 It returns (FoundInExternalDatabase, ParamHash);

   FoundInExternalDatabase must  be set to 1 before return if the user 
   was found in the external database.

   ParamHash is a Perl parameter hash which can contain at least the 
   following fields. These fields are used to populate RT's users 
   database when the user is created.

    email is the email address that RT should use for this user.  
    name is the 'name' attribute RT should use for this user. 
         'name' is used for things like access control and user lookups.
    real_name is what RT should display as the user's name when displaying 
         'friendly' names

=cut

sub lookup_external_user_info {
    my $self      = shift;
    my $email     = shift;
    my $real_name = shift;

    my $FoundInExternalDatabase = 1;
    my %params;

    #name is the RT username you want to use for this user.
    $params{'name'}      = $email;
    $params{'email'}     = $email;
    $params{'real_name'} = $real_name;

    # See RT's contributed code for examples.
    # http://www.fsck.com/pub/rt/contrib/
    return ( $FoundInExternalDatabase, %params );
}

=head2 head

Return the parsed head from this message

=cut

sub head {
    my $self = shift;
    return $self->entity->head;
}

=head2 entity 

Return the parsed Entity from this message

=cut

sub entity {
    my $self = shift;
    return $self->{'entity'};
}

=head2 _setup_mimeparser $parser

A private instance method which sets up a mime parser to do its job

=cut

## TODO: Does it make sense storing to disk at all?  After all, we
## need to put each msg as an in-core scalar before saving it to
## the database, don't we?

## At the same time, we should make sure that we nuke attachments
## Over max size and return them

sub _setup_mime_parser {
    my $self   = shift;
    my $parser = shift;

    my $var_path = RT->var_path;

    # Set up output directory for files; we use RT->var_path instead
    # of File::Spec->tmpdir (e.g., /tmp) beacuse it isn't always
    # writable.
    my $tmpdir;
    if ( -w $var_path ) {
        $tmpdir = File::Temp::tempdir( DIR => $var_path, CLEANUP => 1 );
    }
    elsif ( -w File::Spec->tmpdir ) {
        $tmpdir = File::Temp::tempdir( TMPDIR => 1, CLEANUP => 1 );
    }
    else {
        Jifty->log->fatal(
"Neither the RT var directory ($var_path) nor the system tmpdir (@{[File::Spec->tmpdir]}) are writable; falling back to in-memory parsing!"
        );
    }

    #If someone includes a message, extract it
    $parser->extract_nested_messages(1);

    $parser->extract_uuencode(1);    ### default is false

    if ($tmpdir) {

        # If we got a writable tmpdir, write to disk
        push( @{ $self->{'attachment_dirs'} ||= [] }, $tmpdir );
        $parser->output_dir($tmpdir);
        $parser->filer->ignore_filename(1);

        # Set up the prefix for files with auto-generated names:
        $parser->output_prefix("part");
    # From the MIME::Parser docs:
    # "Normally, tmpfiles are created when needed during parsing, and destroyed automatically when they go out of scope"
    # Turns out that the default is to recycle tempfiles
    # Temp files should never be recycled, especially when running under perl taint checking
        $parser->tmp_recycling(0) if $parser->can('tmp_recycling');
    }
    else {

        # Otherwise, fall back to storing it in memory
        $parser->output_to_core(1);
        $parser->tmp_to_core(1);
        $parser->use_inner_files(1);
    }


}

=head2 parse_email_address string

Returns a list of Email::Address objects
Works around the bug that Email::Address 1.889 and earlier
doesn't handle local-only email addresses (when users pass
in just usernames on the RT system in fields that expect
email Addresses)

We don't handle the case of 
bob, fred@bestpractical.com 
because we don't want to fail parsing
bob, "Falcone, Fred" <fred@bestpractical.com>
The next release of Email::Address will have a new method
we can use that removes the bandaid

=cut

sub parse_email_address {
    my $self           = shift;
    my $address_string = shift;

    $address_string =~ s/^\s+|\s+$//g;

    my @addresses;

    # if it looks like a username / local only email
    if ( $address_string !~ /@/ && $address_string =~ /^\w+$/ ) {
        my $user = RT::Model::User->new( current_user => RT->system_user );
        my ( $id, $msg ) = $user->load($address_string);
        if ($id) {
            push @addresses, Email::Address->new( $user->name, $user->email );
        }
        else {
            Jifty->log->error(
                "Unable to parse an email address from $address_string: $msg");
        }
    }
    else {
        @addresses = Email::Address->parse($address_string);
    }

    return @addresses;

}


sub DESTROY {
    my $self = shift;
    File::Path::rmtree( [ @{ $self->{'attachment_dirs'} } ], 0, 1 )
      if $self->{'attachment_dirs'};
}

1;
