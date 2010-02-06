
use strict;
use warnings;

package RT::Crypt;

require RT::Crypt::GnuPG;
require RT::Crypt::SMIME;

our @PROTOCOLS = ('GnuPG', 'SMIME');

sub Protocols {
    return @PROTOCOLS;
}

sub EnabledProtocols {
    my $self = shift;
    return grep RT->Config->Get($_)->{'Enable'}, $self->Protocols;
}

sub UseForOutgoing {
    return RT->Config->Get('Crypt')->{'Outgoing'};
}

sub EnabledOnIncoming {
    return @{ scalar RT->Config->Get('Crypt')->{'Incoming'} };
}

{ my %cache;
sub LoadImplementation {
    my $class = 'RT::Crypt::'. $_[1];
    return $class if $cache{ $class }++;

    eval "require $class; 1" or do { require Carp; Carp::confess( $@ ) };
    return $class;
} }

# encryption and signatures can be nested one over another, for example:
# GPG inline signed text can be signed with SMIME

sub FindProtectedParts {
    my $self = shift;
    my %args = (
        Entity    => undef,
        Protocols => undef,
        Skip      => {},
        Scattered => 1,
        @_
    );

    my $entity = $args{'Entity'};
    return () if $args{'Skip'}{ $entity };

    my @protocols = $args{'Protocols'}
        ? @{ $args{'Protocols'} } 
        : $self->EnabledOnIncoming;
        
    foreach my $protocol ( @protocols ) {
        my $class = $self->LoadImplementation( $protocol );
        my %info = $class->CheckIfProtected( Entity => $entity );
        next unless keys %info;

        $args{'Skip'}{ $entity } = 1;
        $info{'Protocol'} = $protocol;
        return \%info;
    }

    if ( $entity->effective_type =~ /^multipart\/(?:signed|encrypted)/ ) {
        # if no module claimed that it supports these types then
        # we don't dive in and check sub-parts
        $args{'Skip'}{ $entity } = 1;
        return ();
    }

    my @res;

    # not protected itself, look inside
    push @res, $self->FindProtectedParts(
        %args, Entity => $_, Scattered => 0,
    ) foreach grep !$args{'Skip'}{$_}, $entity->parts;

    if ( $args{'Scattered'} ) {
        my %parent;
        my $filter; $filter = sub {
            $parent{$_[0]} = $_[1];
            unless ( $_[0]->is_multipart ) {
                return () if $args{'Skip'}{$_[0]};
                return $_[0];
            }
            return map $filter->($_, $_[0]), grep !$args{'Skip'}{$_}, $_[0]->parts;
        };
        my @parts = $filter->($entity);
        return @res unless @parts;

        foreach my $protocol ( @protocols ) {
            my $class = $self->LoadImplementation( $protocol );
            my @list = $class->FindScatteredParts(
                Parts   => \@parts,
                Parents => \%parent,
                Skip    => $args{'Skip'}
            );
            next unless @list;

            $_->{'Protocol'} = $protocol foreach @list;
            push @res, @list;
            @parts = grep !$args{'Skip'}{$_}, @parts;
        }
    }

    return @res;
}

sub SignEncrypt {
    my $self = shift;
    my %args = (@_);

    my $entity = $args{'Entity'};
    if ( $args{'Sign'} && !defined $args{'Signer'} ) {
        $args{'Signer'} =
            $self->UseKeyForSigning
            || (Email::Address->parse( $entity->head->get( 'From' ) ))[0]->address;
    }
    if ( $args{'Encrypt'} && !$args{'Recipients'} ) {
        my %seen;
        $args{'Recipients'} = [
            grep $_ && !$seen{ $_ }++, map $_->address,
            map Email::Address->parse( $entity->head->get( $_ ) ),
            qw(To Cc Bcc)
        ];
    }

    my $protocol = delete $args{'Protocol'} || $self->UseForOutgoing;
    my %res = $self->LoadImplementation( $protocol )->SignEncrypt( %args );
    $res{'Protocol'} = $protocol;
    return %res;
}

sub DrySign {
    my $self = shift;
    my %args = ( Protocol => undef, Signer => undef, @_ );
    my $protocol = $args{'Protocol'} || $self->UseForOutgoing;
    return $self->LoadImplementation( $protocol )->DrySign( @_ );
}

sub VerifyDecrypt {
    my $self = shift;
    my %args = (
        Entity    => undef,
        Detach    => 1,
        SetStatus => 1,
        AddStatus => 0,
        @_
    );

    my @res;

    my @protected = $self->FindProtectedParts( Entity => $args{'Entity'} );
    foreach my $protected ( @protected ) {
        my $protocol = $protected->{'Protocol'};
        my $class = $self->LoadImplementation( $protocol );
        my %res = $class->VerifyDecrypt( %args, Info => $protected );
        $res{'Protocol'} = $protocol;
        push @res, \%res;
    }
    return @res;
}

sub ParseStatus {
    my $self = shift;
    my %args = (
        Protocol => undef,
        Status   => '',
        @_
    );
    return $self->LoadImplementation( $args{'Protocol'} )->ParseStatus( $args{'Status'} );
}

=head2 UseKeyForSigning

Returns or sets identifier of the key that should be used for signing.

Returns the current value when called without arguments.

Sets new value when called with one argument and unsets if it's undef.

=cut

{ my $key;
sub UseKeyForSigning {
    my $self = shift;
    if ( @_ ) {
        $key = $_[0];
    }
    return $key;
} }

{ my %key;
# no args -> clear
# one arg -> return preferred key
# many -> set
sub UseKeyForEncryption {
    my $self = shift;
    unless ( @_ ) {
        %key = ();
    } elsif ( @_ > 1 ) {
        %key = (%key, @_);
        $key{ lc($_) } = delete $key{ $_ } foreach grep lc ne $_, keys %key;
    } else {
        return $key{ $_[0] };
    }
    return ();
} }

sub CheckRecipients {
    my $self = shift;
    my @recipients = (@_);

    my ($status, @issues) = (1, ());

    my %seen;
    foreach my $address ( grep !$seen{ lc $_ }++, map $_->address, @recipients ) {
        my %res = $self->GetKeysForEncryption( Recipient => $address );
        if ( $res{'info'} && @{ $res{'info'} } == 1 && $res{'info'}[0]{'TrustLevel'} > 0 ) {
            # good, one suitable and trusted key 
            next;
        }
        my $user = RT::User->new( RT->SystemUser );
        $user->LoadByEmail( $address );
        # it's possible that we have no User record with the email
        $user = undef unless $user->id;

        if ( my $fpr = RT::Crypt->UseKeyForEncryption( $address ) ) {
            if ( $res{'info'} && @{ $res{'info'} } ) {
                next if
                    grep lc $_->{'Fingerprint'} eq lc $fpr,
                    grep $_->{'TrustLevel'} > 0,
                    @{ $res{'info'} };
            }

            $status = 0;
            my %issue = (
                EmailAddress => $address,
                $user? (User => $user) : (),
                Keys => undef,
            );
            $issue{'Message'} = "Selected key either is not trusted or doesn't exist anymore."; #loc
            push @issues, \%issue;
            next;
        }

        my $prefered_key;
        $prefered_key = $user->PreferredKey if $user;
        #XXX: prefered key is not yet implemented...

        # classify errors
        $status = 0;
        my %issue = (
            EmailAddress => $address,
            $user? (User => $user) : (),
            Keys => undef,
        );

        unless ( $res{'info'} && @{ $res{'info'} } ) {
            # no key
            $issue{'Message'} = "There is no key suitable for encryption."; #loc
        }
        elsif ( @{ $res{'info'} } == 1 && !$res{'info'}[0]{'TrustLevel'} ) {
            # trust is not set
            $issue{'Message'} = "There is one suitable key, but trust level is not set."; #loc
        }
        else {
            # multiple keys
            $issue{'Message'} = "There are several keys suitable for encryption."; #loc
        }
        push @issues, \%issue;
    }
    return ($status, @issues);
}

sub GetKeysForEncryption {
    my $self = shift;
    my %args = @_%2? (Recipient => @_) : (Protocol => undef, For => undef, @_ );
    my $protocol = delete $args{'Protocol'} || $self->UseForOutgoing;
    my %res = $self->LoadImplementation( $protocol )->GetKeysForEncryption( %args );
    $res{'Protocol'} = $protocol;
    return %res;
}

sub GetKeysForSigning {
    my $self = shift;
    my %args = @_%2? (Signer => @_) : (Protocol => undef, Signer => undef, @_);
    my $protocol = delete $args{'Protocol'} || $self->UseForOutgoing;
    my %res = $self->LoadImplementation( $protocol )->GetKeysForSigning( %args );
    $res{'Protocol'} = $protocol;
    return %res;
}

sub GetPublicKeyInfo {
    return (shift)->GetKeyInfo( @_, Type => 'public' );
}

sub GetPrivateKeyInfo {
    return (shift)->GetKeyInfo( @_, Type => 'private' );
}

sub GetKeyInfo {
    my $self = shift;
    my %res = $self->GetKeysInfo( @_ );
    $res{'info'} = $res{'info'}->[0];
    return %res;
}

sub GetKeysInfo {
    my $self = shift;
    my %args = @_%2 ? (Key => @_) : ( Protocol => undef, Key => undef, @_ );
    my $protocol = delete $args{'Protocol'} || $self->UseForOutgoing;
    my %res = $self->LoadImplementation( $protocol )->GetKeysInfo( %args );
    $res{'Protocol'} = $protocol;
    return %res;
}

1;