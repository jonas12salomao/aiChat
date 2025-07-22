package AIChat::HookManager;

use strict;
use warnings;

use Plugins;
use Log qw(message debug);

sub new {
    my ($class, $event, $callback) = @_;
    my $self = {
        event => $event,
        callback => $callback,
        hook_id => undef,
    };
    bless $self, $class;
    return $self;
}

sub hook {
    my ($self) = @_;
    $self->{hook_id} = Plugins::addHook($self->{event}, $self->{callback});
}

sub unhook {
    my ($self) = @_;
    Plugins::delHook($self->{hook_id}) if defined $self->{hook_id};
}

1; 