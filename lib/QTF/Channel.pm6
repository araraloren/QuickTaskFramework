
unit module QTF::Channel;

role QChannel is export {
    method send(\item --> QChannel) { ... }

    method poll() { ... }
}

class BaseonLockFreeQueue does QChannel {
    has $.queue;

    method new() {
        if (try require Concurrent::Queue) !=== Nil {
            self.bless(queue => Concurrent::Queue.new);
        } else {
            return Any;
        }
    }

    method send(\item) {
        $!queue.enqueue(item);
        self;
    }

    method poll() {
        my $item = $!queue.dequeue();
        return $item.defined ?? $item !! Nil;
    }
}

class BuiltInChannel does QChannel {
    has $.channel;

    method new() {
        self.bless(channel => Channel.new);
    }

    method send(\item) {
        $!channel.send(item);
        self;
    }

    method poll() {
        $!channel.poll();
    }
}

sub qchannel() is export {
    if (my $channel = BaseonLockFreeQueue.new).defined {
        $channel;
    } else {
        BuiltInChannel.new;
    }
}
