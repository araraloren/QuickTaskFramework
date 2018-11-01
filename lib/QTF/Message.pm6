
unit module QTF::Message;

class QMessage is export {
    has $.type;
    has $.data;
    has $.promise = Promise.new;

    method new($type, $data) {
        self.bless(:$type, :$data);
    }
}
