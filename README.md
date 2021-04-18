[![Build Status](https://travis-ci.org/Leont/raku-actor.svg?branch=master)](https://travis-ci.org/Leont/raku-actor)

NAME
====

Actor - an actor model threading library

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

Actor is a module that implements actor model threading for Raku.

actors are …

INTERFACE
=========

module Actor
------------

### spawn(&starter, *@args, Bool :$monitored --> Handle:D)

This starts a new actor that calls `&starter` with `@args` as its arguments, and returns a handle to that actor. If `$monitored` is true, it will also set up a monitor from the new actor to the current one.

### receive(*@handlers --> Nil)

This will loop through the messages in the queue, and for each message will try to match it in turn to each of the `@handlers` passed to it. If it matches it is taken from the queue and the handler is called with it. Then `receive` returns.

If no such matching message exists, it will wait for a new message to arrive that does match a handler, pushing any non-matching messages to the queue.

### receive-loop(*@handlers --> Nil)

This will call receive in a loop with the given handlers, until one of the handlers calls `last`.

### self-handle(--> Handle:D)

This returns a handle to the current actor.

class Actor::Handle
-------------------

This class represents a handle to an actor

### send(|message --> Nil)

This will send `|message` to that actor.

### alive(--> Bool:D)

This returns true if the actor is still alive.

### add-monitor(handle = self-handle --> Handle::MonitorId)

This sets up a monitor relationship from the invocant handle to the one passed to `add-monitor` (defaulting to the current handle)

### remove-monitor(Handle::MonitorId $monitor)

This removes a monitor from the monitor list of this actor.

monitors
--------

Monitors are watchers on an actor's status. If the actor ends successfully, a message like this is sent:

    (Actor::Exit, $handle, $return-value)

If it dies in an exception, the follow message is sent to the monitoring actor instead.

    (Actor::Error, $handle, $exception)

AUTHOR
======

Leon Timmermans <fawaka@gmail.com>

COPYRIGHT AND LICENSE
=====================

Copyright 2020 Leon Timmermans

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

