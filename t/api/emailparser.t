
use strict;
use warnings;

use RT::Test tests => 13;

ok(require RT::EmailParser);

RT->Config->Set( RTAddressRegexp => undef );
is(RT::EmailParser::IsRTAddress("",""),undef, "Empty emails from users don't match queues without email addresses" );

my $queue = RT::Queue->new($RT::SystemUser);
$queue->Load('General');
$queue->SetCorrespondAddress(" ");
is(RT::EmailParser::IsRTAddress(""," "),undef, 'Catch emails with only whitespace' );
$queue->SetCorrespondAddress("");

RT->Config->Set( CorrespondAddress => " " );
is(RT::EmailParser::IsRTAddress(""," "),undef, 'Catch emails with only whitespace' );
RT->Config->Set( CorrespondAddress => "");

RT->Config->Set( RTAddressRegexp => qr/^rt\@example.com$/i );

is(RT::EmailParser::IsRTAddress("","rt\@example.com"),1, "Regexp matched rt address" );
is(RT::EmailParser::IsRTAddress("","frt\@example.com"),undef, "Regexp didn't match non-rt address" );

my @before = ("rt\@example.com", "frt\@example.com");
my @after = ("frt\@example.com");
ok(eq_array(RT::EmailParser->CullRTAddresses(@before),@after), "CullRTAddresses only culls RT addresses");

{
    require RT::Interface::Email;
    my ( $addr, $name ) =
      RT::Interface::Email::ParseAddressFromHeader('foo@example.com');
    is( $addr, 'foo@example.com', 'addr for foo@example.com' );
    is( $name, undef,             'no name for foo@example.com' );

    ( $addr, $name ) =
      RT::Interface::Email::ParseAddressFromHeader('Foo <foo@example.com>');
    is( $addr, 'foo@example.com', 'addr for Foo <foo@example.com>' );
    is( $name, 'Foo',             'name for Foo <foo@example.com>' );

    ( $addr, $name ) =
      RT::Interface::Email::ParseAddressFromHeader('foo@example.com (Comment)');
    is( $addr, 'foo@example.com', 'addr for foo@example.com (Comment)' );
    is( $name, undef,             'no name for foo@example.com (Comment)' );
}

