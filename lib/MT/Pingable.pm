package MT::Pingable;

use strict;

{
my $driver;
sub _driver {
    my $driver_name = 'MT::Pingable::' . MT->config->PingDriver;
    eval 'require ' . $driver_name;
    if (my $err = $@) {
        die (MT->translate("Bad PingDriver config '[_1]': [_2]", $driver_name, $err));
    }
    my $driver = $driver_name->new;
    die $driver_name->errstr
        if (!$driver || (ref(\$driver) eq 'SCALAR'));
    return $driver;
}

sub _handle {
    my $method = ( caller(1) )[3];
    $method =~ s/.*:://;
    my $driver = $driver ||= _driver();
    return undef unless $driver->can($method);
    $driver->$method(@_);
}

sub release {
    undef $driver;
}
}

sub init_pingable { _handle(@_); }

sub install_properties {
    my $pkg = shift;
    my ($class) = @_;
    my $props = $class->properties;
    my $datasource = $class->datasource;
 
    my $blog_props = MT->model('blog')->properties;
    push @{$blog_props->{child_classes}}, 'MT::TBPing';
    push @{$blog_props->{child_classes}}, 'MT::TrackBack';

    my $cat_props = MT->model('category')->properties;
    push @{$cat_props->{child_classes}}, 'MT::TrackBack';
   
    $props->{column_defs}{allow_pings} = {
        type  => 'boolean',
        not_null => 1        
    };
    $class->install_column('allow_pings');
    $props->{defaults}{allow_pings} = 0;
    
    # Callbacks: clean list of changed columns to only
    # include versioned columns
#    MT->add_callback( 'api_pre_save.' . $datasource, 9, undef, \&mt_presave_obj );
#    MT->add_callback( 'cms_pre_save.' . $datasource, 9, undef, \&mt_presave_obj );
               
    # Callbacks: object-level callbacks could not be 
    # prioritized and thus caused problems with plugins
    # registering a post_save and saving     
#    MT->add_callback( 'api_post_save.' . $datasource, 9, undef, \&mt_postsave_obj );
#    MT->add_callback( 'cms_post_save.' . $datasource, 9, undef, \&mt_postsave_obj );               

#    $class->add_callback( 'post_remove', 0, MT->component('core'), \&mt_postremove_obj );
}

1;
__END__
