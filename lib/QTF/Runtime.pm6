
use QTF::Task;
use QTF::Result;
use QTF::Channel;
use QTF::Message;

unit module QTF::Runtime;

my constant RUNNING = 1;
my constant READY   = 0;

class QType is export {
    enum < Comp Add Get Has Cue Save >;
}

class QRuntime is export {
    has QTask %!task;
    has       %!running;
    has QTask %!remains;
    has Int $.max = 2;
    has Int $!cur = 0;
    has Int $.qqq = 2;
    has QChannel $.channel;
    has atomicint $!running;
    has $.interval = 200;
    has Supplier $!supplier;

    submethod TWEAK(:@tasks) {
        $!channel  = qchannel() unless $!channel.defined;
        atomic-assign($!running, READY);
        %!task{ .name } = .self for @tasks;
        $!supplier.= new;
    }

    method !q_handle(QMessage $m) {
        my $data := $m.data;
        my $p    := $m.promise.vow;
        my $val;

        given $m.type {
            when QType::Comp {
                if !( %!task{$data.[0]}:exists ) {
                    $p.keep(False);
                    return;
                }
                $val = self!q_complete(%!task{$data.[0]} // QTask, $data.[1]);
                if $val !~~ Failure {
                    $p.keep(True);
                } else {
                    $p.break($val);
                }
            }
            when QType::Add | QType::Save {
                $val = %!task{$data.[0].name}:exists;
                if ! $val {
                    %!task{$data.[0].name} = $data.[0];
                }
                $p.keep($val);
            }
            when QType::Get {
                $val = %!task{$data.[0]} // QTask;
                $p.keep($val);
            }
            when QType::Has {
                $p.keep(%!task{$data.[0]}:exists);
            }
            when QType::Cue {
                %!remains{$data.[0].name} = $data;
                $p.keep(True);
            }
            default {
                die "Not recognize type: {$m.type}";
            }
        }
    }

    method !q_complete(QTask:D $task, $r) {
        $task.set-result($r);
    }

    method !q_run(QTask:D $task) {
        my $should-run = $!cur < $!max && $task.ready();

        if $should-run {
            %!running{$task.name} = start {
                $task.initrun(self);
                try {
                    CATCH {
                        default {
                            $task.set-result(Err .self);
                        }
                    }
                    $task.set-result($task.execute-run(self));
                }
            };
            $!cur += 1;
        }
        return $should-run;
    }

    method !q_threadname() {
        %!running.keys;
    }

    method !q_thread(Str:D $name) {
        %!running{$name};
    }

    method !q_init() {
        for %!task {
            .value.init(self);
        }
    }

    method add(QTask:D $task --> Bool) {
        my $found = %!task{$task.name}:exists;
        if ! $found {
            %!task{$task.name} = $task;
        }
        return $found;
    }

    method get(Str:D $name --> QTask) {
        %!task{$name} // QTask;
    }

    method has(Str:D $name --> Bool) {
        %!task{$name}:exists;
    }

    method qcomplete(Str:D $name, $r --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Comp, [ $name, $r ]));
        $qm.promise;
    }

    method qadd(QTask:D $task --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Add, [ $task,    ]));
        $qm.promise;
    }

    method qget(Str:D $name --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Get, [ $name,    ]));
        $qm.promise;
    }

    method qhas(Str:D $name --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Has, [ $name,    ]));
        $qm.promise;
    }

    method qcue(QTask:D $task --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Cue, [ $task,    ]));
        $qm.promise;
    }

    method qsave(QTask:D $task --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Save, [ $task,    ]));
        $qm.promise;
    }

    method Supply( --> Supply) {
        $!supplier.Supply;
    }

    method stop() {
        cas($!running, RUNNING, READY);
    }

    method run() {
        cas($!running, READY, RUNNING);
        self!q_init();
        %!remains = %!task;
        while atomic-fetch($!running) == RUNNING {
            for %!remains.values -> $task {
                if $task.check-dependency(self) {
                    if $task.ready() {
                        if self!q_run($task) {
                            %!remains{$task.name}:delete;
                        }
                    }
                }
            }

            for ^$!qqq {
                my $val = $!channel.poll();
                if $val ~~ QMessage {
                    self!q_handle($val);
                }
            }

            my @thread-name = self!q_threadname();

            for @thread-name -> $name {
                if self!q_thread($name) -> $thr {
                    given $thr.status {
                        when Planned { }
                        when Kept | Broken {
                            my $task = %!running{$name};
                            $!cur -= 1;
                            %!running{$name}:delete;
                            $!supplier.emit: $task;
                        }
                    }
                }
            }

            sleep $!interval / 1000;
        }
    }
}
