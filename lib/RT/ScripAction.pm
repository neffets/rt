# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2008 Best Practical Solutions, LLC
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
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
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

=head1 NAME

  RT::ScripAction - a generic baseclass for RT Actions

=head1 SYNOPSIS

  use RT::ScripAction;

=head1 DESCRIPTION

=head1 METHODS


=cut

package RT::ScripAction;

use strict;
use Scalar::Util;

use base qw/RT::Base/;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );
    $self->_init(@_);
    return $self
}


sub _init {
    my $self = shift;
    my %args = (
        argument       => undef,
        current_user    => undef,
        template_obj    => undef,
        ticket_obj      => undef,
        transaction_obj => undef,
        type           => undef,

        @_
    );

    $self->{'argument'} = $args{'argument'};
    $self->current_user( $args{'current_user'} );
    $self->{'template_obj'}    = $args{'template_obj'};
    $self->{'ticket_obj'}      = $args{'ticket_obj'};
    $self->{'transaction_obj'} = $args{'transaction_obj'};
    $self->{'type'}           = $args{'type'};

#    Scalar::Util::weaken( $self->{'scrip_action_obj'} );
    Scalar::Util::weaken( $self->{'template_obj'} );
#    Scalar::Util::weaken( $self->{'ticket_obj'} );
    Scalar::Util::weaken( $self->{'transaction'} );

}


# Access Scripwide data

sub argument {
    my $self = shift;
    return ( $self->{'argument'} );
}


sub ticket_obj {
    my $self = shift;
    return ( $self->{'ticket_obj'} );
}


sub transaction {
    my $self = shift;
    return ( $self->{'transaction_obj'} );
}


sub template_obj {
    my $self = shift;
    return ( $self->{'template_obj'} );
}


sub type {
    my $self = shift;
    return ( $self->{'Type'} );
}


# Scrip methods

#Do what we need to do and send it out.

sub commit {
    my $self = shift;
    return ( 0, _("Commit Stubbed") );
}


#What does this type of Action does

sub describe {
    my $self = shift;
    return _( "No description for %1", ref $self );
}


#Parse the templates, get things ready to go.

sub prepare {
    my $self = shift;
    return ( 0, _("Prepare Stubbed") );
}

sub hints {
    my ($self) = @_;
    return { class => 'General' };
}

#If this rule applies to this transaction, return true.

sub is_applicable {
    my $self = shift;
    return (undef);
}


sub DESTROY {
    my $self = shift;

    # We need to clean up all the references that might maybe get
    # oddly circular
    $self->{'template_obj'}    = undef;
    $self->{'ticket_obj'} = undef;
    $self->{'transaction_obj'} = undef;
}

1;
