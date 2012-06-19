
use RT::Test nodata => 1, tests => 89;

use strict;
use warnings;

use RT::Tickets;
use RT::Queue;
use RT::CustomField;

# Test Sorting by FreeformSingle custom field.

diag "Create a queue to test with.";
my $queue_name = "CFSortQueue-$$";
my $queue;
{
    $queue = RT::Queue->new( RT->SystemUser );
    my ($ret, $msg) = $queue->Create(
        Name => $queue_name,
        Description => 'queue for custom field sort testing'
    );
    ok($ret, "$queue test queue creation. $msg");
}

# CFs for testing, later we create another one
my %CF;
my $cf_name;

diag "create a CF";
{
    $cf_name = $CF{'CF'}{'name'} = "Order$$";
    $CF{'CF'}{'obj'} = RT::CustomField->new( RT->SystemUser );
    my ($ret, $msg) = $CF{'CF'}{'obj'}->Create(
        Name  => $CF{'CF'}{'name'},
        Queue => $queue->id,
        Type  => 'FreeformSingle',
    );
    ok($ret, "Custom Field $CF{'CF'}{'name'} created");
}

my ($total, @data, @tickets, @test) = (0, ());

sub run_tests {
    my $query_prefix = join ' OR ', map 'id = '. $_->id, @tickets;
    foreach my $test ( @test ) {
        my $query = join " AND ", map "( $_ )", grep defined && length,
            $query_prefix, $test->{'Query'};

        foreach my $order (qw(ASC DESC)) {
            my $error = 0;
            my $tix = RT::Tickets->new( RT->SystemUser );
            $tix->FromSQL( $query );
            $tix->OrderBy( FIELD => $test->{'Order'}, ORDER => $order );

            ok($tix->Count, "found ticket(s)")
                or $error = 1;

            my ($order_ok, $last) = (1, $order eq 'ASC'? '-': 'zzzzzz');
            my $last_id = $tix->Last->id;
            while ( my $t = $tix->Next ) {
                my $tmp;
                next if $t->id == $last_id and $t->Subject eq "-"; # Nulls are allowed to come last, in Pg

                if ( $order eq 'ASC' ) {
                    $tmp = ((split( /,/, $last))[0] cmp (split( /,/, $t->Subject))[0]);
                } else {
                    $tmp = -((split( /,/, $last))[-1] cmp (split( /,/, $t->Subject))[-1]);
                }
                if ( $tmp > 0 ) {
                    $order_ok = 0; last;
                }
                $last = $t->Subject;
            }

            ok( $order_ok, "$order order of tickets is good" )
                or $error = 1;

            if ( $error ) {
                diag "Wrong SQL query:". $tix->BuildSelectQuery;
                $tix->GotoFirstItem;
                while ( my $t = $tix->Next ) {
                    diag sprintf "%02d - %s", $t->id, $t->Subject;
                }
            }
        }
    }
}

@data = (
    { Subject => '-' },
    { Subject => 'a', 'CustomField-' . $CF{CF}{obj}->id => 'a' },
    { Subject => 'b', 'CustomField-' . $CF{CF}{obj}->id => 'b' },
);

@tickets = RT::Test->create_tickets( { Queue => $queue->id, RandomOrder => 1 }, @data);
@test = (
    { Order => "CF.{$cf_name}" },
    { Order => "CF.$queue_name.{$cf_name}" },
);
run_tests();

@data = (
    { Subject => '-' },
    { Subject => 'aa', 'CustomField-' . $CF{CF}{obj}->id => 'aa' },
    { Subject => 'bb', 'CustomField-' . $CF{CF}{obj}->id => 'bb' },
);
@tickets = RT::Test->create_tickets( { Queue => $queue->id, RandomOrder => 1 }, @data);
@test = (
    { Query => "CF.{$cf_name} LIKE 'a'", Order => "CF.{$cf_name}" },
    { Query => "CF.{$cf_name} LIKE 'a'", Order => "CF.$queue_name.{$cf_name}" },
);
run_tests();

@data = (
    { Subject => '-', },
    { Subject => 'a', CF => 'a' },
    { Subject => 'b', CF => 'b' },
    { Subject => 'c', CF => 'c' },
);
@tickets = RT::Test->create_tickets( { Queue => $queue->id, RandomOrder => 1 }, @data);
@test = (
    { Query => "CF.{$cf_name} != 'c'", Order => "CF.{$cf_name}" },
    { Query => "CF.{$cf_name} != 'c'", Order => "CF.$queue_name.{$cf_name}" },
);
run_tests();



diag "create another CF";
{
    $CF{'AnotherCF'}{'name'} = "OrderAnother$$";
    $CF{'AnotherCF'}{'obj'} = RT::CustomField->new( RT->SystemUser );
    my ($ret, $msg) = $CF{'AnotherCF'}{'obj'}->Create(
        Name  => $CF{'AnotherCF'}{'name'},
        Queue => $queue->id,
        Type  => 'FreeformSingle',
    );
    ok($ret, "Custom Field $CF{'AnotherCF'}{'name'} created");
}

# test that order is not affect by other fields (had such problem)
@data = (
    { Subject => '-', },
    { Subject => 'a', CF => 'a', AnotherCF => 'za' },
    { Subject => 'b', CF => 'b', AnotherCF => 'ya' },
    { Subject => 'c', CF => 'c', AnotherCF => 'xa' },
);
@tickets = RT::Test->create_tickets( { Queue => $queue->id, RandomOrder => 1 }, @data);
@test = (
    { Order => "CF.{$cf_name}" },
    { Order => "CF.$queue_name.{$cf_name}" },
    { Query => "CF.{$cf_name} != 'c'", Order => "CF.{$cf_name}" },
    { Query => "CF.{$cf_name} != 'c'", Order => "CF.$queue_name.{$cf_name}" },
);
run_tests();

@tickets = ();

