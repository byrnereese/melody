package TrackBacks::Plugin;

use strict;

sub load_list_filters {
    return { 
        ping => {
            default => {
                label   => 'Non-spam TrackBacks',
                order   => 100,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    require MT::TBPing;
                    $terms->{junk_status} = MT::TBPing::NOT_JUNK();
                },
            },
            my_posts => {
                label   => 'TrackBacks on my entries',
                order   => 200,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    require MT::Entry;
                    my $app = MT->instance;
                    require MT::TBPing;
                    require MT::Trackback;
                    $terms->{junk_status} = MT::TBPing::NOT_JUNK();
                    my $join_str1 = '= tbping_tb_id';
                    my $join_str2 = '= trackback_entry_id';
                    $args->{join}         = MT::Trackback->join_on(
                        undef,
                        { id => \$join_str1, },
                        {   join => MT::Entry->join_on(
                                undef,
                                {   id        => \$join_str2,
                                    author_id => $app->user->id
                                }
                            )
                        },
                    );
                },
            },
            published => {
                label   => 'Published TrackBacks',
                order   => 200,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    $terms->{visible} = 1;
                },
            },
            unpublished => {
                label   => 'Unpublished TrackBacks',
                order   => 300,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    require MT::TBPing;
                    $terms->{junk_status} = MT::TBPing::NOT_JUNK();
                    $terms->{visible}     = 0;
                },
            },
            spam => {
                label   => 'TrackBacks marked as Spam',
                order   => 400,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    require MT::TBPing;
                    $terms->{junk_status} = MT::TBPing::JUNK();
                },
            },
            last_7_days => {
                label   => 'All TrackBacks in the last 7 days',
                order   => 700,
                handler => sub {
                    my ( $terms, $args ) = @_;
                    my $ts = time - 7 * 24 * 60 * 60;
                    $ts = epoch2ts( MT->app->blog, $ts );
                    $terms->{created_on} = [ $ts, undef ];
                    $args->{range_incl}{created_on} = 1;
                    $terms->{junk_status} = MT::TBPing::NOT_JUNK();
                },
            }
        }
    }
}

sub load_wizard_app {
    return {
        optional_packages => {
            'HTML::Entities' => {
                link => 'http://search.cpan.org/dist/HTML-Entities',
                label =>
                    'This module is needed to encode special characters, but this feature can be turned off using the NoHTMLEntities option in mt-config.cgi.',
            },
            'LWP::UserAgent' => {
                link => 'http://search.cpan.org/dist/LWP',
                label =>
                    'This module is needed if you wish to use the TrackBack system, the weblogs.com ping, or the MT Recently Updated ping.',
            },
        }
    }
}

sub load_backup_instructions {
    return {
        'trackback'     => {
            'order' => 510
        },

        # Comments should be backed up after TBPing
        # because saving a comment ultimately triggers
        # MT::TBPing::save.

        # Ping should be backed up after Trackback.
        'tbping'        => {
            'order' => 520
        },
        'ping'          =>  {
            'order' => 520
        },
        'ping_cat'      => {
            'order' => 520
        },
    }
}

# TODO - need to make sure this loads, maybe load on init callback?
package MT::TBPing;

sub parents {
    my $obj = shift;
    {
        blog_id => MT->model('blog'),
        tb_id => MT->model('trackback'),
    };
}

package MT::Trackback;

sub restore_parent_ids {
    my $obj = shift;
    my ($data, $objects) = @_;

    my $result = 0;
    my $blog_class = MT->model('blog');
    my $new_blog = $objects->{$blog_class . '#' . $data->{blog_id}};
    if ($new_blog) {
        $data->{blog_id} = $new_blog->id;
    } else {
        return 0;
    }                            
    if (my $cid = $data->{category_id}) {
        my $cat_class = MT->model('category');
        my $new_obj = $objects->{$cat_class . '#' . $cid};
        unless ($new_obj) {
            $cat_class = MT->model('folder');
            $new_obj = $objects->{$cat_class . '#' . $cid};
        }
        if ($new_obj) {
            $data->{category_id} = $new_obj->id;
            $result = 1;
        }
    } elsif (my $eid = $data->{entry_id}) {
        my $entry_class = MT->model('entry');
        my $new_obj = $objects->{$entry_class . '#' . $eid};
        unless ($new_obj) {
            $entry_class = MT->model('page');
            $new_obj = $objects->{$entry_class . '#' . $eid};
        }
        if ($new_obj) {
            $data->{entry_id} = $new_obj->id;
            $result = 1;
        }
    }
    $result;
}

# Added for backwards compat
package MT::Blog;
sub email_all_pings { return $_[0]->email_new_pings == 1; }
sub email_attn_reqd_pings { return $_[0]->email_new_pings == 2; }

package MT::Category;
sub ping_url_list {
    my $cat = shift;
    return [] unless $cat->ping_urls && $cat->ping_urls =~ /\S/;
    [ split /\r?\n/, $cat->ping_urls ];
}

1;
__END__
