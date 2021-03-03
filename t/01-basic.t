use v6.d;
use Test;
use Actor;

my $thread = spawn {
	receive
		-> $other {
			$other.send(:foo);
			$other.send('bar');
		};
	42;
}, :monitored;

ok($thread.alive, 'Created thread');

$thread.send(self-handle);

is(self-handle, self-handle, 'Two handles to the same actor are equal');

my $state = 0;
receive-loop
	-> Exit, $identifier, $result {
		is($result, 42, 'Got right result');
		is($identifier, $thread, 'Got the right thread');
		is($state++, 1, 'State is now 1');
		leave-loop;
	},
	-> Error, $identifier, $error {
		note($error);
		flunk('Got right result');
		is($state++, 1, 'State is now 1');
		leave-loop;
	},
	-> 'bar' {
		is($state++, 0, 'Received bar');
		receive
			-> 'bar' {
				flunk('Should match foo after bar');
				diag('Matched bar instead')
			},
			-> :$foo {
				ok($foo, 'Should match foo after bar');
			}
	};

await $thread;

done-testing;
