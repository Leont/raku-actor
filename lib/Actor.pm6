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

enum Result is export(:DEFAULT, :enums) <Exit Error>;

class Handle { ... }
my class Receiver { ... }

my class Mailbox {
	has Queue:D $!queue = Queue.new;
	has Promise:D $.promise = Promise.new;
	has Handle:D @!monitors;
	has Lock:D $!lock = Lock.new;
	has @!status;

	multi submethod BUILD() {
	}
	multi submethod BUILD(:&starter!, :$monitor!, :@args) {
		$!channel = Channel.new;
		$!promise = start {
			my $*RECEIVER = Receiver.new(:mailbox(self));
			starter(|@args);
		}

		@!monitors.push($monitor) with $monitor;

		$!promise.then: {
			$!lock.protect: {
				@!status = $!promise.status === Kept ?? (Exit, self.WHICH, $!promise.result) !! (Error, self.WHICH, $!promise.cause);
				for @!monitors -> $monitor {
					$monitor.send: @!status;
				}
			}
		}
	}

	method send(@value) {
		$!queue.enqueue(@value);
	}
	method receive() {
		return |$!queue.dequeue;
	}

	method add-monitor(Handle:D $handle) {
		$!lock.protect: {
			if $!promise {
				$handle.send: @!status;
			}
			else {
				@!monitors.push: $handle;
			}
		}
	}
}

my sub receiver { ... }

class Handle does Awaitable {
	has Mailbox:D $!mailbox is required;

	submethod BUILD(Mailbox:D :$!mailbox) {}

	method send(+@arguments --> Nil) {
		$!mailbox.send(@arguments);
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
}

my class Stop is Exception { }

my class Receiver {
	has Mailbox:D $!mailbox is required;
	has Any @!buffer;
	submethod BUILD(Mailbox:D :$!mailbox) {}

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
			my @message = $!mailbox.receive;
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
		return Handle.new(:$!mailbox);
	}
}

sub spawn(&starter, *@args, Bool :$monitored --> Handle:D) is export(:DEFAULT, :spawn, :functions) {
	my Handle $monitor = $monitored ?? receiver.handle !! Handle;
	my Mailbox $mailbox = Mailbox.new(:$monitor, :&starter, :@args);
	return Handle.new(:$mailbox);
}

my $loading-thread = $*THREAD;
my $initial-receiver = Receiver.new(:mailbox(Mailbox.new));

my sub receiver() {
	return $*THREAD === $loading-thread ?? $initial-receiver !! $*RECEIVER orelse die "This thread has no receiver";
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
