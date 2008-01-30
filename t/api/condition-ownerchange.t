
use strict;
use warnings;
use RT::Test; use Test::More; 
plan tests => 11;
use RT;



{

my $q = RT::Model::Queue->new(current_user => RT->system_user);
$q->create(name =>'ownerChangeTest');

ok($q->id, "Created a scriptest queue");

my $s1 = RT::Model::Scrip->new(current_user => RT->system_user);
my ($val, $msg) =$s1->create( queue => $q->id,
             scrip_action => 'User Defined',
             scrip_condition => 'On Owner Change',
             custom_is_applicable_code => '',
             custom_prepare_code => 'return 1',
             custom_commit_code => '
                my ($status, $msg) = $self->ticket_obj->set_priority($self->ticket_obj->priority+1);
                unless ( $status ) {
                    Jifty->log->error($msg);
                    return (0);
                }
                return(1);
            ',
             template => 'Blank'
    );
ok($val,$msg);

my $ticket = RT::Model::Ticket->new(current_user => RT->system_user);
my ($tv,$ttv,$tm) = $ticket->create(queue => $q->id,
                                    subject => "hair on fire",
                                    initial_priority => '20'
                                    );
ok($tv, $tm);
ok($ticket->set_owner('root'));
is ($ticket->priority , '21', "Ticket priority is set right");


ok($ticket->steal);
is ($ticket->priority , '22', "Ticket priority is set right");
ok($ticket->untake);
is ($ticket->priority , '23', "Ticket priority is set right");
ok($ticket->take);
is ($ticket->priority , '24', "Ticket priority is set right");






}

1;
