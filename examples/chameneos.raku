use v6.d;

use Actor;

sub spell(Int $n --> Str) {
	state @names = <zero one two three four five six seven eight nine>;
	my Str $next = @names[$n % 10];
	return $n >= 10 ?? spell(($n / 10).Int) ~ " " ~ $next !! $next;
}

enum Color <blue red yellow>;

my @table = (
	[ blue, yellow, red ],
	[ yellow, red, blue ],
	[ red, blue, yellow ],
);

sub show-complements() {
	for (blue, red, yellow) -> $i {
		for (blue, red, yellow) -> $j {
			say "$i + $j -> ", @table[$i][$j];
		}
	}
}

sub print-header(@colors) {
	say "";
	for @colors -> $color {
		print " $color";
	}
	say "";
}

sub broker(Int $meetings-count) {
	my Int $seen = 0;
	receive-loop -> Actor::Handle $handle-left, Color $color-left {
		receive -> Actor::Handle $handle-right, Color $color-right {
			$handle-left.send($handle-right, $color-right);
			$handle-right.send($handle-left, $color-left);
			leave-loop if ++$seen == $meetings-count;
		};
	};
}

class Stop {}

sub cleanup(Int(Cool) $color-count is copy) {
	my Int $summary = 0;
	receive-loop
		-> Actor::Handle $other, Color $ {
			$other.send(Stop);
		},
		-> Int $mismatch {
			$summary += $mismatch;
			if --$color-count == 0 {
				say spell($summary);
				leave-loop;
			}
		}
}

sub chameneos(Color $current is copy, Actor::Handle $broker) {
	my ($meetings, $met-self) = 0, 0;
	my $self = self-handle;
	$broker.send($self, $current);

	receive-loop
		-> Actor::Handle $other, Color $color {
			$meetings++;
			$current = @table[$current][$color];
			$met-self++ if $other === $self;
			$broker.send($self, $current);
		},
		-> Stop $ {
			say "$meetings {spell($met-self)}";
			$broker.send($meetings);
			last;
		}
}

sub run(@colors, Int $count) {
	print-header(@colors);
	my $broker = spawn {
		broker($count);
		cleanup(@colors);
	}
	for @colors -> $color {
		spawn(-> { chameneos($color, $broker) });
	}
	return $broker;
}

sub MAIN(Int $count = 10000) {
	show-complements();
	await run([ blue, red, yellow ], $count);
	await run([ blue, red, yellow, red, yellow, blue, red, yellow, red, blue ], $count);
	say "";
}
