use utf8;
use strict;
use warnings;
use Config::Pit;
use Encode;
use WebService::CybozuCom;

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
my $bulletin = $c->show_bulletin();
for my $row (@$bulletin){
    print Encode::encode_utf8 sprintf("%sさんが%s「%s」を書きました %s\n",
        $row->{username},
        $row->{category},
        $row->{title},
        $row->{url},
    );
}

