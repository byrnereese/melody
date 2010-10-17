package MT::Log::TBPing;

our @ISA = qw( MT::Log );

__PACKAGE__->install_properties({
    class_type => 'ping',
});

sub class_label { MT->translate("TrackBacks") }

sub description {
    my $log = shift;
    my $id = int($log->metadata);
    my $ping = $log->metadata_object;
    my $msg;
    if ($ping) {
        $msg = $ping->to_hash->{'tbping.excerpt_html'};
    } else {
        $msg = MT->translate("TrackBack # [_1] not found.", $log->metadata);
    }
    $msg;
}

1;
__END__
