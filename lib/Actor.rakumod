use v6.c;
unit module Actor:ver<0.0.1>:auth<cpan:LEONT>;

enum Result is export(:DEFAULT, :enums) <Exit Error>;

class Handle { ... }

my class Stop is Exception { }

my class Mailbox {
	has Channel:D $!channel = Channel.new;
	has Promise:D $.promise = Promise.new;
	has Handle:D %!monitors;
	has Lock:D $!lock = Lock.new;
	has @!status;
	has Capture @!buffer;

	my class MonitorId {
		my atomicint $counter = 0;
		has Int $!id = $counter⚛++;
		method WHICH() {
			return $!id.WHICH;
		}
	}

	multi submethod BUILD() {
	}
	multi submethod BUILD(:&starter!, :$monitor!, :@args) {
		$!channel = Channel.new;
		$!promise = start {
			my $*RECEIVER = self;
			LEAVE {
				$!channel.close;
				Nil while $!channel.poll;
			}
			starter(|@args);
		}

		%!monitors{MonitorId.new} = $monitor with $monitor;

		$!promise.then: {
			$!lock.protect: {
				@!status = $!promise.status === Kept ?? (Exit, self.handle, $!promise.result) !! (Error, self.handle, $!promise.cause);
				for %!monitors.values -> $monitor {
					$monitor.send: |@!status;
				}
			}
		}
	}

	method send(Capture $value) {
		$!channel.send($value);
		CATCH { when X::Channel::SendOnClosed { }}
	}

	method receive(@blocks --> Any) {
		for ^@!buffer -> $index {
			my Capture $message = @!buffer[$index];
			for @blocks -> &candidate {
				if $message ~~ &candidate.signature {
					@!buffer.splice($index, 1);
					return candidate(|$message);
				}
			}
		}
		loop {
			my Capture $message = $!channel.receive;
			for @blocks -> &candidate {
				return candidate(|$message) if $message ~~ &candidate.signature;
			}
			@!buffer.push: $message;
		}
	}

	method receive-loop(@blocks --> Any) {
		loop {
			receive(@blocks);
		}
		CATCH { when Stop {
			return;
		}}
	}

	method handle(--> Handle:D) {
		return Handle.new(:mailbox(self));
	}

	method add-monitor(Handle:D $handle --> MonitorId:D) {
		$!lock.protect: {
			my $id = MonitorId.new;
			if $!promise {
				$handle.send: |@!status;
			}
			else {
				%!monitors{$id} = $handle;
			}
			return $id;
		}
	}

	method remove-monitor(MonitorId:D $id --> Nil) {
		$!lock.protect: {
			return ?%!monitors{$id}:delete;
		}
	}
}

my $loading-thread = $*THREAD;
my $initial-receiver = Mailbox.new;

my sub receiver() {
	return $*THREAD === $loading-thread ?? $initial-receiver !! $*RECEIVER // die "This thread has no receiver";
}

class Handle does Awaitable {
	has Mailbox:D $!mailbox is required;

	submethod BUILD(Mailbox:D :$!mailbox) {}

	method send(|arguments --> Nil) {
		$!mailbox.send(arguments);
	}

	method get-await-handle(--> Awaitable::Handle:D) {
		return $!mailbox.promise.get-await-handle;
	}

	method alive(--> Bool:D) {
		return not $!mailbox.promise;
	}

	method add-monitor(Handle:D $handle = receiver.handle) {
		$!mailbox.add-monitor: $handle;
	}

	method WHICH(--> ObjAt:D) {
		return $!mailbox.WHICH;
	}

	method Str() {
		return $!mailbox.WHICH.Str.subst(/Mailbox/, 'Handle');
	}
}

sub spawn(&starter, *@args, Bool :$monitored --> Handle:D) is export(:DEFAULT, :spawn, :functions) {
	my Handle $monitor = $monitored ?? receiver.handle !! Handle;
	my Mailbox $mailbox = Mailbox.new(:$monitor, :&starter, :@args);
	return Handle.new(:$mailbox);
}

sub receive(*@blocks --> Nil) is export(:DEFAULT, :receive, :functions) {
	receiver.receive(@blocks);
}

sub receive-loop(*@blocks --> Nil) is export(:DEFAULT, :receive, :functions) {
	receiver.receive-loop(@blocks);
}

sub self-handle(--> Handle:D) is export(:DEFAULT, :self-handle, :functions) {
	return receiver.handle;
}

sub leave-loop(--> Nil) is export(:DEFAULT, :leave-loop, :functions) {
	Stop.new.throw;
}

=begin pod

=head1 NAME

Actor - an actor model threading library

=head1 SYNOPSIS

=begin code :lang<raku>

use v6.d;
use Actor;

my $actor = spawn {
    receive-loop
        -> Str $message, Actor::Handle $other {
            say "Message $message";
            $other.send($message);
        },
        -> Int :$number, Str :$message {
            say "Message $message" if $number %% 7;
        },
        -> "stop" {
            last;
        };
}

$actor.send("message", self-handle);
receive
    -> Str $message {
        $actor.send(:42number, :$message);
        $actor.send("stop");
    };

await $actor;

=end code

=head1 DESCRIPTION

Actor is a module that implements actor model threading for Raku.

actors are …

=head1 INTERFACE

=head2 module Actor

=head3 spawn(&starter, *@args, Bool :$monitored --> Handle:D)

This starts a new actor that calls C<&starter> with C<@args> as its arguments, and returns a handle to that actor. If C<$monitored> is true, it will also set up a monitor from the new actor to the current one.

=head3 receive(*@handlers --> Nil)

This will loop through the messages in the queue, and for each message will try to match it in turn to each of the C<@handlers> passed to it. If it matches it is taken from the queue and the handler is called with it. Then C<receive> returns.

If no such matching message exists, it will wait for a new message to arrive that does match a handler, pushing any non-matching messages to the queue.

=head3 receive-loop(*@handlers --> Nil)

This will call receive in a loop with the given handlers, until one of the handlers calls C<last>.

=head3 self-handle(--> Handle:D)

This returns a handle to the current actor.

=head2 class Actor::Handle

This class represents a handle to an actor

=head3 send(|message --> Nil)

This will send C<|message> to that actor.

=head3 alive(--> Bool:D)

This returns true if the actor is still alive.

=head3 add-monitor(handle = self-handle --> Handle::MonitorId)

This sets up a monitor relationship from the invocant handle to the one passed to C<add-monitor> (defaulting to the current handle)

=head3 remove-monitor(Handle::MonitorId $monitor)

This removes a monitor from the monitor list of this actor.

=head2 monitors

Monitors are watchers on an actor's status. If the actor ends successfully, a message like this is sent:

 (Actor::Exit, $handle, $return-value)

If it dies in an exception, the follow message is sent to the monitoring actor instead.

 (Actor::Error, $handle, $exception)

=head1 AUTHOR

Leon Timmermans <fawaka@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
