use utf8;
use strict;
use warnings;
use Config::Pit;
use Encode;
use WebService::CybozuCom;

my $date = undef; #undef or 'yyyy/mm/dd';
my $c;

{# prepare
    local $ENV{EDITOR} = 'vi';
    my $pit = pit_get('cybozu.com', require => {
            domain   => 'your group name',
            username => 'your username',
            password => 'your password',
        }
    );

    $c = WebService::CybozuCom->new(
        %$pit,
    );

}

$c->login();
my $schedule = $c->show_schedule( date => $date );

for my $row (@$schedule){
    my $notify;
    unless($row->{time_string}){ #banner
        $notify = sprintf("%sは%sの予定があります( %s )",   ($date || '本日'),                      $row->{title}, $row->{url});
    }
    else{
        $notify = sprintf("%sの%sに%sの予定があります( %s )", ($date || '本日'), $row->{time_string}, $row->{title}, $row->{url});
    }
    print(Encode::encode_utf8($notify));
    print "\n";
}
