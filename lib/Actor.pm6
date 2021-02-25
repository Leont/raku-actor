use v6.c;
unit module Actor:ver<0.0.1>:auth<cpan:LEONT>;

class Queue {
	has Lock:D $!lock = Lock.new;
	has Lock::ConditionVariable:D $!condition = $!lock.condition;
	has Any @!queue;

	method enqueue(Any $value --> Nil) {
		$!lock.protect: {
			@!queue.push: $value;
			$!condition.signal;
		};
	}
	method dequeue(--> Any) {
		$!lock.protect: {
			$!condition.wait while not @!queue;
			return @!queue.shift;
		};
	}
}

enum Result <Exit Error>;

class Handle { ... }

my class ActorQueue is Queue {
	has Promise:D $.promise = Promise.new;
	has Handle:D @!monitors = Array[Handle:D].new;

	submethod TWEAK {
		$!promise.then({
			my @message = $!promise.status === Kept ?? (Exit, $!promise.result) !! (Error, $!promise.cause);
			for @!monitors -> $monitor {
				$monitor.send: @message;
			}
		});
	}

	method add-monitor(Handle:D $handle) {
		@!monitors.push: $handle;
	}
}

class Handle does Awaitable {
	has ActorQueue:D $!queue is required;

	submethod BUILD(ActorQueue:D :$!queue) {}

	method send(*@arguments --> Nil) {
		$!queue.enqueue: @arguments;
	}

	method get-await-handle(--> Awaitable::Handle:D) {
		return $!queue.promise.get-await-handle;
	}

	method alive(--> Bool:D) {
		return $!queue.promise ~~ Planned;
	}

	method add-monitor(Handle:D $handle = $*MAILBOX.handle) {
		$!queue.add-monitor: $handle;
	}

	method WHICH(--> ObjAt:D) {
		return $!queue.WHICH;
	}
}

my class Stop is Exception { }

my class Mailbox {
	has ActorQueue:D $!queue is required;
	has Any @!buffer;
	submethod BUILD(ActorQueue:D :$!queue) {}

	method receive(@blocks --> Any) {
		for 0 ..^ @!buffer -> $index {
			my @message = |@!buffer[$index];
			for @blocks -> &candidate {
				if @message ~~ &candidate.signature {
					@!buffer.splice($index, 1);
					return candidate(|@message);
				}
			}
		}
		loop {
			my @message = |$!queue.dequeue;
			for @blocks -> &candidate {
				return candidate(|@message) if @message ~~ &candidate.signature;
			}
			@!buffer.push: @message;
		}
	}
	method receive-loop(@blocks --> Any) {
		FOO:
		loop {
			receive(@blocks);
			CATCH { when Stop {
				last FOO;
			}}
		}
	}
	method handle(--> Handle:D) {
		return Handle.new(:$!queue);
	}
}

sub spawn(&callable, *@args --> Handle:D) is export(:DEFAULT, :spawn, :functions) {
	my $queue = ActorQueue.new;
	my $promise = start {
		my $*MAILBOX = Mailbox.new(:$queue);
		$queue.promise.keep: callable(|@args);
		CATCH { default {
			$queue.promise.break: $_;
		} }
	}
	return Handle.new(:$queue);
}

sub receive(*@blocks --> Nil) is export(:DEFAULT, :receive, :functions) {
	$*MAILBOX.receive(@blocks);
}

sub receive-loop(*@blocks --> Nil) is export(:DEFAULT, :receive, :functions) {
	$*MAILBOX.receive-loop(@blocks);
}

sub self-handle(--> Handle:D) is export(:DEFAULT, :self-handle, :functions) {
	return $*MAILBOX.handle;
}

sub leave-loop(--> Nil) is export {
	Stop.new.throw;
}

=begin pod

=head1 NAME

Actor - an actor model threading library

=head1 SYNOPSIS

=begin code :lang<perl6>

use Actor;

my $actor = spawn {
	given receive() {
		when Int {
			say "We got"
		}
		when :(Int, Str) {
		}
	}
}

$actor.send("message");
$actor.send(42, "Danger, Will Robinson");

=end code

=head1 DESCRIPTION

Actor is a module that implements actor model threading for perl 6.

=head1 AUTHOR

Leon Timmermans <fawaka@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
