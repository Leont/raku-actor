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

my class ActorQueue is Queue {
	has Promise:D $.promise = Promise.new;
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

	method WHICH(--> ObjAt:D) {
		return $!queue.WHICH;
	}
}

my class Mailbox {
	has ActorQueue:D $!queue is required;
	submethod BUILD(ActorQueue:D :$!queue) {}

	method receive(--> Any) {
		return |$!queue.dequeue;
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

sub receive(--> Any) is export(:DEFAULT, :receive, :functions) {
	return $*MAILBOX.receive;
}

sub self-handle(--> Handle:D) is export(:DEFAULT, :self-handle, :functions) {
	return $*MAILBOX.handle;
}

=begin pod

=head1 NAME

Actor - blah blah blah

=head1 SYNOPSIS

=begin code :lang<perl6>

use Actor;

=end code

=head1 DESCRIPTION

Actor is ...

=head1 AUTHOR

Leon Timmermans <fawaka@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
