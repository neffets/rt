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
package RT::Shredder::Dependency;

use strict;
use RT::Shredder::Constants;
use RT::Shredder::Exceptions;

my %FlagDescs = ( DEPENDS_ON, 'depends on', VARIABLE, 'resolvable dependency', WIPE_AFTER, 'delete after' );

sub new {
    my $proto = shift;
    my $self = bless( {}, ref $proto || $proto );
    $self->set(@_);
    return $self;
}

sub set {
    my $self = shift;
    my %args = ( flags => DEPENDS_ON, @_ );
    my @keys = qw(flags base_object target_object);
    @$self{@keys} = @args{@keys};

    return;
}

sub as_string {
    my $self = shift;
    my $res  = $self->base_object->_as_string;
    $res .= " " . $self->flags_as_string;
    $res .= " " . $self->target_object->_as_string;
    return $res;
}

sub flags { return $_[0]->{'flags'} }

sub flags_as_string {
    my $self = shift;
    my @res  = ();
    foreach ( sort keys %FlagDescs ) {
        if ( $self->flags() & $_ ) {
            push( @res, $FlagDescs{$_} );
        }
    }
    push @res, 'no flags' unless (@res);
    return "(" . join( ',', @res ) . ")";
}

sub base_object   { return $_[0]->{'base_object'} }
sub target_object { return $_[0]->{'target_object'} }
sub object        { return shift()->{ ( {@_} )->{type} . "_object" } }

sub target_class { return ref $_[0]->{'target_object'} }
sub base_class   { return ref $_[0]->{'base_object'} }
sub class        { return ref shift()->object(@_) }

1;