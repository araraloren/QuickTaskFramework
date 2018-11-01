
use QTF::Result;

unit module QTF::Task;

class QTaskStatus is export {

    enum < Ready Running Finish >;

    has $.status is rw;
    has $.result is rw;

    method new($s, $r = Err Any) {
        self.bless(status => $s, result => $r);
    }

    method eq($status) {
        $!status === $status;
    }

    method ne($status) {
        $!status !=== $status;
    }
}

role QTask is export {
    has Str $.name;
    has @.dependency;
    has QTaskStatus $!status;

    multi method new(Str:D $name, *%args) {
        self.bless(:$name, |%args);
    }

    multi method new(Str:D $name, @dependency, *%args) {
        self.bless(:$name, :@dependency, |%args);
    }

    method init($runtime) {
        $!status = QTaskStatus.new(QTaskStatus::Ready);
    }

    method initrun($runtime) { }

    method ready() {
        return $!status.eq: QTaskStatus::Ready;
    }

    method running() {
        return $!status.eq: QTaskStatus::Running;
    }

    method finish() {
        return $!status.eq: QTaskStatus::Finish;
    }

    method dependency() {
        @!dependency;
    }

    method check-dependency($runtime --> Bool) {
        my $ret  = True;
        my @dep  = self.dependency();

        if +@dep > 0 {
            for @dep -> $dep {
                my $task;

                if $dep ~~ QTask {
                    $task = $dep;
                }
                elsif $dep ~~ Str {
                    $task = $runtime.get($dep) or fail "No task named {$dep}";
                }
                else {
                    fail "There is something not task or task name: {$dep.gist}";
                }

                given $task.status {
                    when QTaskStatus::Ready {
                        if ! $runtime.has($task.name) {
                            $runtime.qcue($task);
                        }
                        $ret &&= False;
                    }
                    when QTaskStatus::Finish {
                        $ret &&= $task.result().is-ok();
                    }
                    default {
                        $ret &&= False;
                    }
                }
            }
        }
        return $ret;
    }

    method add-dependency($dependency --> ::?CLASS:D) {
        die "Task is not allow to add dependency when qtask running or finished.";
        @!dependency.push($dependency);
        self;
    }

    method status() {
        $!status.status();
    }

    method set-result($result) {
        if ! self.finish() {
            $!status = QTaskStatus.new(QTaskStatus::Finish, $result);
        }
        else {
            fail "The task is already finished!";
        }
    }

    method result() {
        $!status.result;
    }

    method execute-run($runtime --> QResult) {
        if self.ready() {
            $!status.status = QTaskStatus::Running;
            return self.run($runtime);
        }
        fail "Task is already running!";
    }

    method run($runtime --> QResult) { ... }
}

class CodeTask does QTask is export {
    has &.code;

    multi method new(Str:D $name, &code:($rt)) {
        self.bless(:$name, :&code);
    }

    multi method new(Str:D $name, &code:($rt), @dependency) {
        self.bless(:$name, :&code, :@dependency);
    }

    method run($runtime --> QResult) {
        return &!code($runtime);
    }
}

class CommandTask does QTask is export {
    has $.bin;
    has $.out = "";
    has $.err = "";
    has @.args= [];

    multi method new(Str:D $name, Str:D $bin, @args) {
        self.bless(:$name, :$bin, :@args);
    }

    multi method new(Str:D $name, Str:D $bin, @args, @dependency) {
        self.bless(:$name, :$bin, :@args, :@dependency);
    }

    method run($runtime --> QResult) {
        my $asyncproc = Proc::Async.new($!bin, @!args);

        $asyncproc.stdout.tap( -> $str { $!out ~= $str; });
        $asyncproc.stderr.tap( -> $str { $!err ~= $str; });

        my $promise = $asyncproc.start;
        try {
            my $proc = $promise.result;
            return Ok $proc.exitcode;
            CATCH {
                default {
                    return Ok $proc.exitcode;
                }
            }
        }
    }
}

class MethodTask does QTask is export {
    has &.method;

    multi method new(Str:D $name, &method) {
        self.bless(:$name, :&method);
    }

    multi method new(Str:D $name, &method, @dependency) {
        self.bless(:$name, :&method, :@dependency);
    }

    method run($runtime --> QResult) {
        return &!method(self, $runtime);
    }
}

multi sub qtask(Str:D $name, Method $m) is export {
    MethodTask.new($name, $m);
}

multi sub qtask(Str:D $name, Method $m, @dependency) is export {
    MethodTask.new($name, $m, @dependency);
}

multi sub qtask(Str:D $name, &cb) is export {
    CodeTask.new($name, &cb);
}

multi sub qtask(Str:D $name, &cb, @dependency) is export {
    CodeTask.new($name, &cb, @dependency);
}

multi sub qtask(Str:D $name, Str:D $bin, @args) is export {
    CommandTask.new($name, $bin, @args);
}

multi sub qtask(Str:D $name, Str:D $bin, @args, @dependency) is export {
    CommandTask.new($name, $bin, @args, @dependency);
}
