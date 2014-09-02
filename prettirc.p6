use v6;

my %PSEUDOS;

class Pseudo {
    has Str $.text;
    has Str $.color = '#' ~ ((0..0xCC).pick xx 3).fmt('%02x', '');
    submethod BUILD(Str :$!text!) { %PSEUDOS{$!text} = self }
}

my $linenum = 1;
class IrcLine {
    has DateTime $.timestamp;
    has Int $.number = $linenum++;
}

class IrcMessage is IrcLine {
    has Pseudo $.speaker;
    has Str $.message;
}

class IrcEvent is IrcLine { has Str $.descr }

grammar IrcLine::Grammar {

    token TOP { ^ [ <message> || <event> ] \n? $ }

    token message { <timestamp> ' <' <pseudo> '> ' <blah> }

    token event { <timestamp> ' -!- ' <blah> }

    token timestamp {
        '['
            $<year>=(\d**4) '-' $<month>=(\d**2) '-' $<day>=(\d**2)
        ' '
            $<hour>=(\d**2) ':' $<minute>=(\d**2) ':' $<second>=(\d**2)
        ']'
    }

    token pseudo { \w+ }

    token blah { \N* }
}

class IrcLine::Actions {

    method TOP($/) {
        for $/.values -> $v {
            make $v.made;
        }
    }

    method message($/) {
        make IrcMessage.new(
            timestamp => $<timestamp>.made,
            speaker   => $<pseudo>.made,
            message   => ~$<blah>,
        );
    }

    method event($/) {
        make IrcEvent.new(
            timestamp => $<timestamp>.made,
            descr     => ~$<blah>,
        );
    }

    method timestamp($/) {
        make DateTime.new(
            year     => +$<year>, month  => +$<month>,  day    => +$<day>,
            hour     => +$<hour>, minute => +$<minute>, second => +$<second>,
            timezone => $*TZ,
        );
    }

    method pseudo($/) {
        make %PSEUDOS{~$/} :exists ?? %PSEUDOS{~$/} !! Pseudo.new(:text(~$/))
    }

}

sub MAIN(Str $path?) {
    my $fh = $path.defined ?? open $path !! $*IN;
    my @lines;

    my $actions = IrcLine::Actions.new;
    for $fh.lines -> $line {
        my $m = IrcLine::Grammar.parse($line, :$actions);
        die "Can't parse the following line:\n$line" unless $m;
        push @lines, $m.made;
    }

    for @lines { .gist.say }
}
