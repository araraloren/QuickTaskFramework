
use QTF::Result;

unit module QTF::Task;

class QTaskStatus is export {

    enum < Ready Running Finish Unknow >;

    has $.status is rw;
    has $.result is rw;

    method new($s, $r = Ok Any) {
        self.bless(status => $s, result => $r);
    }

    method ready($r = Ok Any) {
        self.new(QTaskStatus::Ready, $r);
    }

    method running($r = Ok Any) {
        self.new(QTaskStatus::Running, $r);
    }

    method finish($r) {
        self.new(QTaskStatus::Finish, $r);
    }

    method is-ready() {
        $!status === QTaskStatus::Ready;
    }

    method is-running() {
        $!status === QTaskStatus::Running;
    }

    method is-finish() {
        $!status === QTaskStatus::Finish;
    }

    method eq($status) {
        $!status === $status;
    }

    method ne($status) {
        $!status !=== $status;
    }

    method Bool() {
        self.defined;
    }

    method what() {
        $!result.what();
    }
}

role QTask is export {
    has Str $.name;
    has @.dependency;

    multi method new(Str:D $name, *%args) {
        self.bless(:$name, |%args);
    }

    multi method new(Str:D $name, @dependency, *%args) {
        self.bless(:$name, :@dependency, |%args);
    }

    method init($runtime) { }

    method initrun($runtime) { }

    method dependency() {
        @!dependency;
    }

    # This is called by runtime, at same THEAD
    method check-dependency($runtime) {
        my $ret  = True;
        my @dep  = self.dependency();

        if +@dep > 0 {
            for @dep -> $dep {
                my $status = $runtime.status($dep);

                if ( !$status.defined ) && ($dep ~~ QTask) {
                    $runtime.qcue($dep);
                    next;
                }

                next if !$status.defined;

                given $status.status {
                    when QTaskStatus::Ready {
                        $ret &&= False;
                    }
                    when QTaskStatus::Finish {
                        if ! $status.so {
                            return QTaskStatus.finish(Err "Dependency {$dep.Str} finished with err: {$status.result.what}!");
                        }
                    }
                    default {
                        $ret &&= False;
                    }
                }
            }
        }
        return $ret ?? QTaskStatus.running() !! QTaskStatus.ready();
    }

    method add-dependency($dependency --> ::?CLASS:D) {
        die "Task is not allow to add dependency when qtask running or finished.";
        @!dependency.push($dependency);
        self;
    }

    method execute-run($runtime --> QResult) {
        return self.run($runtime);
    }

    method Str() {
        $!name;
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

multi sub qtask(Str:D $name, @dependency, Method $m) is export {
    MethodTask.new($name, $m, @dependency);
}

multi sub qtask(Str:D $name, &cb) is export {
    CodeTask.new($name, &cb);
}

multi sub qtask(Str:D $name, &cb, @dependency) is export {
    CodeTask.new($name, &cb, @dependency);
}

multi sub qtask(Str:D $name, @dependency, &cb) is export {
    CodeTask.new($name, &cb, @dependency);
}

multi sub qtask(Str:D $name, Str:D $bin, @args) is export {
    CommandTask.new($name, $bin, @args);
}

multi sub qtask(Str:D $name, Str:D $bin, @args, @dependency) is export {
    CommandTask.new($name, $bin, @args, @dependency);
}

multi sub qtask(Str:D $name, @dependency, Str:D $bin, @args) is export {
    CommandTask.new($name, $bin, @args, @dependency);
}
