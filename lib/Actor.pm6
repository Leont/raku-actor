use v6.c;
unit module Actor:ver<0.0.1>:auth<cpan:LEONT>;

enum Result is export(:DEFAULT, :enums) <Exit Error>;

class Handle { ... }

my class Stop is Exception { }

my class Mailbox {
	has Channel:D $!channel = Channel.new;
	has Promise:D $.promise = Promise.new;
	has Handle:D @!monitors;
	has Lock:D $!lock = Lock.new;
	has @!status;
	has Any @!buffer;

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
		$!channel.send(@value);
		CATCH { when X::Channel::SendOnClosed { }}
	}

	method receive(@blocks --> Any) {
		for ^@!buffer -> $index {
			my @message = |@!buffer[$index];
			for @blocks -> &candidate {
				if @message ~~ &candidate.signature {
					@!buffer.splice($index, 1);
					return candidate(|@message);
				}
			}
		}
		loop {
			my @message = |$!channel.receive;
			for @blocks -> &candidate {
				return candidate(|@message) if @message ~~ &candidate.signature;
			}
			@!buffer.push: @message;
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

my $loading-thread = $*THREAD;
my $initial-receiver = Mailbox.new;

my sub receiver() {
	return $*THREAD === $loading-thread ?? $initial-receiver !! $*RECEIVER orelse die "This thread has no receiver";
}

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
