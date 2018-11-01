
use QTF::Task;
use QTF::Runtime;

unit module QTF::Tools;

my $default_rt = Any;

sub default-runtime(*%args) is export is rw {
    $default_rt // do {
        $default_rt = QRuntime.new(|%args);
        $default_rt;
    };
}

multi sub task(Str:D $name, &cb) is export {
    default-runtime().add(qtask($name, &cb));
}

multi sub task(Str:D $name, &cb, @dependency) is export {
    default-runtime().add(qtask($name, &cb, @dependency));
}

multi sub task(Str:D $name, Str:D $bin, @args) is export {
    default-runtime().add(qtask($name, $bin, @args));
}

multi sub task(Str:D $name, Str:D $bin, @args, @dependency) is export {
    default-runtime().add(qtask($name, $bin, @args, @dependency));
}

multi sub task() is export {
    default-runtime.run();
}
