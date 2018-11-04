
use QTF::Task;
use QTF::Tools;
use QTF::Result;

# get perl6.org page, get the NEWS

constant PERL6ORG = 'https://www.perl6.org';

task 'check', -> $r {
    my $lwp = (try require LWP::Simple) !=== Nil;

    if ! $lwp {
        $r.qcue(
            qtask 'curl', ['check', ], 'curl', [ PERL6ORG, ];
        );
        $r.qcue(
            qtask 'end', ['curl', ], -> $r {
                Ok 1;
            }
        );
    }
    ($lwp ?? Ok(1) !! Err(0));
}
task 'lwp', ['check', ], -> $r {
    if $r.qstatus('check').result.so {
        $r.qcue(
            qtask 'end', ['lwp', ], -> $r {
                Ok 1;
            }
        );

        require LWP::Simple;

        my $page = LWP::Simple.new.get(PERL6ORG);

        Ok $page;
    } else {
        Err 0;
    }
}

start task() ;

react {
    whenever Supply.interval(1) {
        for < check lwp curl end > {
            if (my $s = default-runtime().qstatus($_).result) {
                say $_, "\t---=> ", $s.status;
                if $_ eq 'end' && $s.is-finish() {
                    if $s.result.is-ok() {
                        if default-runtime().qstatus('check').result.so {
                            &show-new-version(default-runtime().qstatus('lwp').result.what);
                        } else {
                            &show-new-version(default-runtime().qget('curl').result.out);
                        }
                    } else {
                        say "Can not get the page: ", $s.result.what;
                    }
                    default-runtime.qstop();
                    done;
                }
            }
        }
    }
}

sub show-new-version(Str:D $page) {
    if $page ~~ / 'NEW:</b>' <-[<]>+? (\d+\.\d+) <-[<]>+ 'Released!' \</ {
        say "The new version of Rakudo Star is ", $0.Str;
    }
}
