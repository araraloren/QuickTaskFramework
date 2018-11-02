
use QTF::Task;
use QTF::Result;
use QTF::Channel;
use QTF::Message;

unit module QTF::Runtime;

my constant RUNNING = 1;
my constant READY   = 0;

class QType is export {
    enum < Set Add Get Has Cue Save Stat >;
}

class QThread {
    has $.task;
    has $.thread;
}

class QRuntime is export {
    has QTask %!task;
    has       @!running;
    has QTask %!remain;
    has       %!status;
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
        @!running[$_] = Any for ^$!max;
    }

    method !q_handle(QMessage $m) {
        my $data := $m.data;
        my $p    := $m.promise.vow;
        my $val;

        given $m.type {
            when QType::Set {
                my $name = $data.[0];
                $val = %!status{$name}.is-finish();
                if ! $val {
                    %!status{$name} = QTaskStatus.finish($data.[1]);
                }
                $p.keep(! $val);
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
                %!remain{$data.[0].name} = $data.[0];
                $p.keep(True);
            }
            when QType::Stat {
                if !( %!task{$data.[0]}:exists ) {
                    $p.keep(QTaskStatus);
                    return;
                }
                $p.keep(%!status{$data.[0]});
            }
            default {
                die "Not recognize type: {$m.type}";
            }
        }
    }

    method !q_run(QTask:D $task) {
        my $should-run = $!cur < $!max;
        if $should-run {
            for ^$!max {
                if ! @!running[$_].defined {
                    @!running[$_] = QThread.new(
                        task => $task,
                        thread => start {
                            $task.initrun(self);
                            try {
                                CATCH {
                                    default {
                                        self.qset( $task.name, Err .self );
                                    }
                                }
                                self.qset($task.name, $task.execute-run(self));
                            }
                        }
                    );
                    last;
                }
            }
            $!cur += 1;
        }
        return $should-run;
    }

    method !q_init() {
        for %!task {
            .value.init(self);
            %!status{.value.name} = QTaskStatus.new(QTaskStatus::Ready);
        }
    }

    # Call this method without q* at same THREAD or before run

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

    multi method status(Str:D $name --> QTaskStatus) {
        %!status{$name} // QTaskStatus;
    }

    multi method status(QTask:D $task --> QTaskStatus) {
        %!status{$task.name} // QTaskStatus;
    }

    # Threadsafe method

    method qset(Str:D $name, $r --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Set, [ $name, $r ]));
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

    multi method qstatus(Str:D $name --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Stat, [ $name,    ]));
        $qm.promise;
    }

    multi method qstatus(QTask:D $task --> Promise) {
        $!channel.send(my $qm = QMessage.new(QType::Stat, [ $task.name,]));
        $qm.promise;
    }

    method Supply( --> Supply) {
        $!supplier.Supply;
    }

    method qstop() {
        cas($!running, RUNNING, READY);
    }

    method run() {
        cas($!running, READY, RUNNING);
        self!q_init();
        %!remain = %!task;
        while atomic-fetch($!running) == RUNNING || $!cur > 0 {
            for %!remain.values -> $task {
                my ($name, $run) = ($task.name, False);

                if (%!status{$name}:exists) {
                    given %!status{$name}.status {
                        when QTaskStatus::Finish {
                            %!remain{$name}:delete;        
                        }
                        when QTaskStatus::Ready {
                            $run = True;
                        }
                    }
                } else {
                    $run = True;
                }

                if $run {
                    my $next-status = $task.check-dependency(self);

                    given $next-status.status  {
                        when QTaskStatus::Finish {
                            %!remain{$name}:delete;
                            %!status{$name} = $next-status;
                        }
                        when QTaskStatus::Running {
                            if self!q_run($task) {
                                %!remain{$name}:delete;
                                %!status{$name} = $next-status;
                            }
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

            for @!running <-> $thread {
                if $thread.defined {
                    given $thread.thread.status {
                        when Planned { }
                        when Kept | Broken {
                            $!cur -= 1;
                            $!supplier.emit: $thread.task;
                            $thread = Any;
                        }
                    }
                }
            }

            sleep $!interval / 1000;
        }
        $!supplier.done;
    }
}
