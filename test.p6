
use QTF::Task;
use QTF::Result;
use QTF::Runtime;
use QTF::Tools;

constant $PROXY = 'socks5://192.168.0.100:18995';

task 'if', -> $r {
    say "Checking shadowsocks-libev";
    if ! "shadowsocks-libev".IO.e {
        $r.qcue( qtask 'clone',
            'git', [ "-c", "http.proxy=$PROXY", "-c", "https.proxy=$PROXY", "clone", 'https://github.com/shadowsocks/shadowsocks-libev', ] );
    }
    Ok 1;
};

task 'check',
    'ls', [ "shadowsocks-libev/", ], "shadowsocks-libev".IO.e ?? [ "if", ] !! [ "clone", ];

start task();

react {
    "START".say;

    whenever Supply.interval(3) {
        for < if check > {
            given default-runtime().qget($_) {
                say " >>> ", .result.name, " ==> ", .result.status, " >> ", .result.dependency();
            }
        }

        if default-runtime().qget('if').result.finish() &&
            default-runtime().qget('check').result.finish() {
                my $check = default-runtime().qget('check').result;

                say "File get from github ==> ";
                say $check.out;

                done;
            }
    }
}
