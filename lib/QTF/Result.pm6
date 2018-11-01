
unit module QTF::Result;

class QStatus is export {
    enum < Ok Err >;
}

class QResult is export {
    has $.status;
    has $.what;

    method is-ok(--> Bool) {
        $!status === QStatus::Ok;
    }

    method is-err(--> Bool) {
        $!status === QStatus::Err;
    }

    method what() {
        $!what;
    }
}

sub Ok($what) is export {
    QResult.new(
        status => QStatus::Ok,
        what   => $what,
    );
}

sub Err($what) is export {
    QResult.new(
        status => QStatus::Err,
        what   => $what,
    );
}

multi sub infix:<==>(QResult $l, QResult $r) is export {
    ($l.status() === $r.status()) && ($l.what() == $r.what());
}

multi sub infix:<!=>(QResult $l, QResult $r) is export {
    ! ($l == $r);
}
