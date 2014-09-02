use v6;

# PARSING ###################################################################

my $linenum = 1;
class IrcLine {
    has DateTime $.timestamp;
    has Int $.number = $linenum++;
}

class IrcMessage is IrcLine {
    has Str $.speaker;
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
            speaker   => ~$<pseudo>,
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

}

# HTML ######################################################################

role Formatter {
    method format(IrcLine @lines --> Str) {...}
}

my %PSEUDOS;

my @COLORS := gather loop {
    my Int @rgb = (0..0xFF).pick xx 3;
    my $level = [+] @rgb;
    take '#' ~ @rgb.fmt('%02x', '') if 50 < $level < 500;
};

class Pseudo {
    has Str $.text;

    has Str $.color = shift @COLORS;

    submethod BUILD(Str :$!text!) { %PSEUDOS{$!text} = self }
    method new(Str $text) {
        %PSEUDOS{$text} :exists ?? %PSEUDOS{$text} !! self.bless(:$text)
    }
}

class HtmlFormatter does Formatter {

    sub html-entities-encode(Str $str --> Str) {
        $str.trans:
            /'&'/ => '&amp;',
            /'<'/ => '&lt;', /'>'/ => '&gt;',
    }

    method format(IrcLine @lines --> Str) {
        my $strlines = [~] do for @lines {
            my $n = .number;
            my $t = qq{<a id="l$n" href="#l$n" class="date">}
                  ~ format-timestamp(.timestamp)
                  ~ '</a>';
            {
                when IrcEvent { $t ~= ' ' ~ format-descr(.descr) }
                when IrcMessage {
                    $t ~= ' ' ~ format-pseudo(.speaker)
                        ~ ' ' ~ format-message(.message)
                }
                default { die "Unknown IrcLine subclass: " ~ .WHAT }
            }
            $t ~ "<br>\n"
        }
        q:to[STDSTYLE] ~ qc:to[END]
        <!DOCTYPE html>
        <head>
            <meta charset="utf-8">
        </head>
        <body>
            <section style="font-family: monospace">
                <style scoped type="text/css">
                    .date { color: #bbbbbb; text-decoration: none; }
                    .date:hover { color: #555555 }
                    .event { font-style: italic; font-size: 90% }
                    .event:not(:hover) { color: #bbbbbb }
        STDSTYLE
                    {
                        [~] do for %PSEUDOS.kv {
                            my $color = $^b.color;
                            q:s[.p_$^a { font-weight: bold; color: $color } ]
                        }
                    }
                </style>
                {$strlines}
            </section>
        </body>
        END
    }

    sub format-timestamp(DateTime $dt --> Str) {
        '[' ~ $dt.Date
            ~ ' ' ~ join(':', ($dt.hour, $dt.minute, $dt.second)».fmt('%02d'))
            ~ ']'
    }

    sub format-pseudo(Str $str --> Str) {
        my $pseudo = Pseudo.new( html-entities-encode($str) );
        '<span class="p_' ~ $pseudo.text ~ '">&lt;' ~ $pseudo.text ~ '&gt;</span>'
    }

    sub format-message(Str $str is copy --> Str) {
        $str = html-entities-encode($str);
        $str ~~ s:g{ « https? '://' <[\w./#:-]>+ } = qq|<a href="{~$/}">{~$/}</a>|;
        $str
    }

    sub format-descr(Str $str is copy --> Str) {
        $str = html-entities-encode($str);
        # Anonymize IPv4s
        $str ~~ s:g{ « [\d ** 1..3] ** 4 % '.' » } = 'i.p.v.4';
        '<span class="event">' ~ $str ~ '</span>'
    }
}

# MAIN ######################################################################

sub MAIN(Str $path?) {
    my $fh = $path.defined ?? open $path !! $*IN;
    my IrcLine @lines;

    my $actions = IrcLine::Actions.new;
    for $fh.lines -> $line {
        my $m = IrcLine::Grammar.parse($line, :$actions);
        die "Can't parse the following line:\n$line" unless $m;
        push @lines, $m.made;
    }

    say HtmlFormatter.new.format: @lines
}
