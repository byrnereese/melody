package MT::CMS::Dashboard;

use strict;
use MT::Util qw( epoch2ts encode_html );

sub dashboard {
    my $app     = shift;
    my $q       = $app->query;
    my (%param) = @_;

    if ( $app->request('fresh_login') ) {
        if ( !$q->param('blog_id') ) {

            # return to the last blog they visted, if any
            my $fav_blogs = $app->user->favorite_blogs || [];
            my $blog_id = $fav_blogs->[0] if @$fav_blogs;
            $q->param( 'blog_id', $blog_id ) if $blog_id;
            $app->delete_param('blog_id') unless $app->is_authorized;
        }
    }

    my $param = \%param;

    $param->{redirect}   ||= $q->param('redirect');
    $param->{permission} ||= $q->param('permission');
    $param->{saved}      ||= $q->param('saved');

    $param->{system_overview_nav}
      = $q->param('blog_id') ? 0 : defined( $q->param('blog_id') ) ? 1 : 0;
    $param->{quick_search}   = 0;
    $param->{no_breadcrumbs} = 1;
    $param->{screen_class}   = "dashboard";
    $param->{screen_id}      = "dashboard";

    my $default_widgets = {
                 'blog_stats' =>
                   { param => { tab => 'entry' }, order => 1, set => 'main' },
                 'this_is_you-1' => { order => 1, set => 'sidebar' },
                 'mt_shortcuts'  => { order => 2, set => 'sidebar' },
                 'melody_news'   => { order => 3, set => 'sidebar' },
    };

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local');
    foreach my $subdir (qw( uploads userpics )) {
        $param->{support_path}
          = File::Spec->catdir( $app->static_file_path, 'support', $subdir );
        if ( !$fmgr->exists( $param->{support_path} ) ) {
            $fmgr->mkpath( $param->{support_path} );
        }
        if (    $fmgr->exists( $param->{support_path} )
             && $fmgr->can_write( $param->{support_path} ) )
        {
            $param->{has_uploads_path} = 1;
        }
        else {
            $param->{has_uploads_path} = 0;
            last;
        }
    }
    unless ( exists $param->{has_uploads_path} ) {
        unless ( $fmgr->exists( $param->{support_path} ) ) {

            # the path didn't exist - change the warning a little
            $param->{support_path}
              = File::Spec->catdir( $app->static_file_path, 'support' );
        }
    }
    eval { require MT::Image; MT::Image->new or die; };
    $param->{can_use_userpic} = $@ ? 0 : 1;

    # We require that the determination of the 'single blog mode'
    # state be done PRIOR to the generation of the widgets
    $app->build_blog_selector($param);
    $app->load_widget_list( 'dashboard', $param, $default_widgets );
    $param = $app->load_widgets( 'dashboard', $param, $default_widgets );
    return $app->load_tmpl( "dashboard.tmpl", $param );
} ## end sub dashboard

sub new_version_widget {
    my $app = shift;
    my ( $tmpl, $param ) = @_;

    push @{ $param->{feature_loop} ||= [] },
      {
        feature_label => MT->translate('Better, Stronger, Faster'),
        feature_url   => $app->help_url('mt42/performance.html'),
        feature_description =>
          MT->translate(
            'Movable Type has undergone a significant overhaul in all aspects of performance. Memory utilization has been reduced, publishing times have been increased significantly and search is now 100x faster!'
          ),
      },
      {
        feature_label => MT->translate('Module Caching'),
        feature_url   => $app->help_url('mt42/module-caching.html'),
        feature_description =>
          MT->translate(
            'Template module and widget content can now be cached in the database to dramatically speed up publishing.'
          ),
      },
      {
        feature_label =>
          MT->translate('Improved Template and Design Management'),
        feature_url => $app->help_url('mt42/design-enhancements.html'),
        feature_description =>
          MT->translate(
            'The template editing interface has been enhanced to make designers more efficient at updating their site\'s design. The default templates have also been dramatically simplified to make it easier for you to edit and create the site you want.'
          ),
      },
      {
        feature_label => MT->translate('Threaded Comments'),
        feature_url   => $app->help_url('mt42/threading.html'),
        feature_description =>
          MT->translate(
            'Allow commenters on your blog to reply to each other increasing user engagement and creating more dynamic conversations.'
          ),
      };
} ## end sub new_version_widget

sub this_is_you_widget {
    my $app = shift;
    my ( $tmpl, $param ) = @_;

    my $user = $app->user;

    # User profile data
    # Number of posts by this user
    require MT::Entry;
    $param->{publish_count} = MT::Entry->count( { author_id => $user->id, } );
    $param->{draft_count} = MT::Entry->count(
                   { author_id => $user->id, status => MT::Entry::HOLD(), } );
    if ( $param->{publish_count} ) {
        my $iter =
          MT::Entry->sum_group_by(
                                   { author_id => $user->id, },
                                   {
                                      sum   => 'comment_count',
                                      group => ['author_id']
                                   }
          );
        my ( $count, $author_id ) = $iter->();
        $param->{comment_count} = $count;
    }

    require MT::Permission;
    my @perm = MT::Permission->load( { author_id => $app->user->id } );
    my @blogs = map { $_->blog_id } grep {
             $_->can_create_post
          || $_->can_publish_post
          || $_->can_edit_all_posts
    } @perm;
    $param->{can_list_entries} = @blogs ? 1 : 0;
    @blogs = map { $_->blog_id } grep { $_->can_view_feedback } @perm;
    $param->{can_list_comments} = @blogs ? 1 : 0;

    my $last_post = MT::Entry->load( {
                                        author_id => $user->id,
                                        status    => MT::Entry::RELEASE(),
                                     },
                                     {
                                        sort      => 'authored_on',
                                        direction => 'descend',
                                        limit     => 1,
                                     }
    );

    if ($last_post) {
        $param->{last_post_id}        = $last_post->id;
        $param->{last_post_blog_id}   = $last_post->blog_id;
        $param->{last_post_blog_name} = $last_post->blog->name;
        $param->{last_post_ts}        = $last_post->authored_on;
        my $perms = MT::Permission->load(
            { blog_id => $last_post->blog_id, author_id => $app->user->id } );
        $param->{last_post_can_edit}
          = $perms && $perms->can_edit_entry( $last_post, $app->user );
    }

    if ( my ($url) = $user->userpic_url() ) {
        $param->{author_userpic_url} = $url;
    }
    $param->{author_userpic_width}  = 50;
    $param->{author_userpic_height} = 50;
} ## end sub this_is_you_widget

sub melody_news_widget {
    my $app = shift;
    my ( $tmpl, $param ) = @_;

    $param->{news_html} = get_newsbox_content($app) || '';

    # $param->{learning_mt_news_html} = get_lmt_content($app) || '';
}

sub get_newsbox_content {
    my $app         = shift;
    my $newsbox_url = $app->config('NewsboxURL');
    if ( $newsbox_url && $newsbox_url ne 'disable' ) {
        return MT::Util::get_newsbox_html( $newsbox_url, 'NW' );
    }
    return q();
}

sub get_lmt_content {
    my $app         = shift;
    my $newsbox_url = $app->config('LearningNewsURL');
    if ( $newsbox_url && $newsbox_url ne 'disable' ) {
        return MT::Util::get_newsbox_html( $newsbox_url, 'LW' );
    }
    return q();
}

sub mt_blog_stats_widget {
    my $app = shift;
    my ( $tmpl, $param ) = @_;

    # For stats shown on this page
    stats_generation_handler( $app, $param ) or return;

    my $tabs = $app->registry('blog_stats_tabs') or return;
    $tabs = $app->filter_conditional_list( $tabs, 'dashboard',
                                           ( $param->{widget_scope} || '' ) );

    $param->{tab_html_head} = '';
    {
        local $param->{main};
        local $param->{html_head};

        my %cfgs;
        my $stat_url = delete $param->{stat_url};
        while ( my ( $tab_id, $url ) = each %$stat_url ) {
            $param->{has_stat_urls} = 1;
            $cfgs{$tab_id} = { param => { stat_url => $url } };
        }
        $app->build_widgets(
               set         => 'blog_stats',
               param       => $param,
               widgets     => $tabs,
               widget_cfgs => \%cfgs,
               passthru_param =>
                 [qw( html_head js_include tabs active_stats_panel_updates )],
        ) or return;

        $param->{blog_stats} = $param->{main};
        $param->{tab_html_head} .= $param->{html_head};
    }
} ## end sub mt_blog_stats_widget

sub stats_generation_handler {
    my $app = shift;
    my ($param) = @_;

    if ( lc( MT->config('StatsCachePublishing') ) eq 'off' ) {
        return;
    }

    my $cache_time = 60 * MT->config('StatsCacheTTL');   # cache for x minutes

    my $stats_static_path = create_stats_directory( $app, $param ) or return;

    my $tabs = $app->registry('blog_stats_tabs') or return;

    while ( my ( $tab_id, $tab ) = each %$tabs ) {
        next if !$tab->{stats};

        my $file = "${tab_id}.xml";
        $param->{stat_url}->{$tab_id} = $stats_static_path . '/' . $file;
        my $path = File::Spec->catfile( $param->{support_path}, $file );

        my $time = ( stat($path) )[9] if -f $path;

        if ( lc( MT->config('StatsCachePublishing') ) eq 'onload' ) {
            if ( !$time || ( time - $time > $cache_time ) ) {
                unless (
                         generate_dashboard_stats(
                                            $app, $param, $tab, $tab_id, $path
                         )
                  )
                {
                    delete $param->{stat_url}->{$tab_id};
                }
            }
        }
        else {
            return;
        }
    } ## end while ( my ( $tab_id, $tab...))

    1;
} ## end sub stats_generation_handler

sub create_stats_directory {
    my $app = shift;
    my ($param) = @_;

    my $blog_id = $app->blog ? $app->blog->id : 0;
    my $user    = $app->user;
    my $user_id = $user->id;

    my $static_path      = $app->static_path;
    my $static_file_path = $app->static_file_path;

    if ( -f File::Spec->catfile( $static_file_path, "mt.js" ) ) {
        $param->{static_file_path} = $static_file_path;
    }
    else {
        return;
    }

    my $low_dir = sprintf( "%03d", $user_id % 1000 );
    my $sub_dir = sprintf( "%03d", $blog_id % 1000 );
    my $top_dir = $blog_id > $sub_dir ? $blog_id - $sub_dir : 0;
    $param->{support_path} =
      File::Spec->catdir( $static_file_path, 'support', 'dashboard', 'stats',
                          $top_dir, $sub_dir, $low_dir );

    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new('Local');
    unless ( $fmgr->exists( $param->{support_path} ) ) {
        $fmgr->mkpath( $param->{support_path} );
        unless ( $fmgr->exists( $param->{support_path} ) ) {

            # the path didn't exist - change the warning a little
            $param->{support_path}
              = File::Spec->catdir( $app->static_file_path, 'support' );
            return;
        }
    }

    return
        $static_path
      . 'support/dashboard/stats/'
      . $top_dir . '/'
      . $sub_dir . '/'
      . $low_dir;
} ## end sub create_stats_directory

sub mt_blog_stats_widget_entry_tab {
    my ( $app, $tmpl, $param ) = @_;

    my $user    = $app->user;
    my $blog    = $app->blog;
    my $blog_id = $blog->id if $blog;

    $param->{editable} = $user->is_superuser;
    if ( $blog && !$param->{editable} ) {
        $param->{editable} = $user->permissions($blog_id)->can_edit_all_posts;
    }

    my $entries = sub {
        my $args
          = { limit => 10, sort => 'authored_on', direction => 'descend', };
        if ( !$user->is_superuser && !$blog_id ) {
            my $join_str = '= entry_blog_id';
            $args->{join} =
              MT::Permission->join_on(
                                       undef,
                                       {
                                          blog_id   => \$join_str,
                                          author_id => $user->id
                                       },
              );
        }
        my @e = MT::Entry->load( { (
                                       $blog_id ? ( blog_id => $blog_id ) : ()
                                    ),
                                 },
                                 $args
        );
        \@e;
    };

    require MT::Promise;
    my $ctx = $tmpl->context;
    $ctx->stash( 'entries', MT::Promise::delay($entries) );
} ## end sub mt_blog_stats_widget_entry_tab

sub generate_dashboard_stats {
    my $app = shift;
    my ( $param, $tab, $tab_id, $path ) = @_;

    my $gen_stats = $tab->{stats};
    $gen_stats = $app->handler_to_coderef($gen_stats);

    my %counts = $gen_stats->( $app, $tab );

    unless ( create_dashboard_stats_file( $app, $path, \%counts ) ) {
        delete $param->{stat_url}->{$tab_id};
    }

    1;
}

sub create_dashboard_stats_file {
    my $app = shift;
    my ( $file, $data ) = @_;

    my $support_dir = File::Spec->catdir( $app->static_file_path, "support" );

    local *FOUT;
    if ( !open( FOUT, ">$file" ) ) {
        return;
    }

    print FOUT <<EOT;
<?xml version="1.0"?>
<rsp status_code="0" status_message="Success">
  <daily_counts>
EOT
    my $now = time;
    for ( my $i = 120; $i >= 1; $i-- ) {
        my $ds = substr(
                         epoch2ts(
                                   $app->blog,
                                   $now - ( ( $i - 1 ) * 60 * 60 * 24 )
                         ),
                         0, 8
        ) . 'T00:00:00';
        my $count = $data->{$ds} || 0;
        print FOUT qq{    <count date="$ds">$count</count>\n};
    }
    print FOUT <<EOT;
  </daily_counts>
</rsp>
EOT
    close FOUT;
} ## end sub create_dashboard_stats_file

sub generate_dashboard_stats_entry_tab {
    my $app = shift;
    my ($tab) = @_;

    my $blog_id = $app->blog ? $app->blog->id : 0;
    my $user    = $app->user;
    my $user_id = $user->id;

    my $entry_class = $app->model('entry');
    my $terms = { status => MT::Entry::RELEASE() };
    my $args = {
                 group => [
                            "extract(year from authored_on)",
                            "extract(month from authored_on)",
                            "extract(day from authored_on)"
                 ],
    };

    require MT::Util;
    my @ts
      = MT::Util::offset_time_list( time - ( 121 * 24 * 60 * 60 ), $blog_id );
    my $earliest = sprintf( '%04d%02d%02d%02d%02d%02d',
                            $ts[5] + 1900,
                            $ts[4] + 1,
                            @ts[ 3, 2, 1, 0 ] );
    $terms->{authored_on} = [ $earliest, undef ];
    $args->{range_incl}{authored_on} = 1;

    $terms->{blog_id} = $blog_id if $blog_id;
    if ( !$user->is_superuser && !$blog_id ) {
        my $join_str = '= entry_blog_id';
        $args->{join} =
          MT::Permission->join_on(
                                   undef,
                                   {
                                      blog_id   => \$join_str,
                                      author_id => $user_id
                                   },
          );
    }

    my $entry_iter = $entry_class->count_group_by( $terms, $args );
    my %counts;
    while ( my ( $count, $y, $m, $d ) = $entry_iter->() ) {
        my $date = sprintf( "%04d%02d%02dT00:00:00", $y, $m, $d );
        $counts{$date} = $count;
    }

    %counts;
} ## end sub generate_dashboard_stats_entry_tab

sub mt_blog_stats_tag_cloud_tab {
    my ( $app, $tmpl, $param ) = @_;

    my $blog = $app->blog;
    my $blog_id = $blog->id if $blog;

    my $terms = {};
    my $args  = {};
    $terms->{blog_id}           = $blog_id if $blog_id;
    $terms->{object_datasource} = 'entry';
    $args->{group}              = ['tag_id'];
    $args->{sort}               = '1';                    # sort by count(*)
    $args->{direction}          = 'descend';
    $args->{limit}              = 100;
    my $join_str = '= objecttag_tag_id';
    $args->{join} = MT::Tag->join_on(
                                      undef,
                                      {
                                         id         => \$join_str,
                                         is_private => 1
                                      },
                                      { not => { is_private => 1 } }
    );

    my $iter = $app->model('objecttag')->count_group_by( $terms, $args );
    my @tag_loop;
    my @tag_ids;
    my $ntags = 0;
    my $min   = undef;
    my $max   = undef;
    while ( my ( $count, $tag_id ) = $iter->() ) {
        $ntags += $count;
        $min = defined $min ? ( $count < $min ? $count : $min ) : $count;
        $max = defined $max ? ( $count > $max ? $count : $max ) : $count;
        push @tag_loop, { id => $tag_id, count => $count };
        push @tag_ids, $tag_id;
    }

    if (@tag_ids) {
        my $iter = MT::Tag->load_iter( { id => \@tag_ids } );
        my %tags;
        while ( my $t = $iter->() ) {
            $tags{ $t->id } = $t->name;
        }
        $_->{name} = $tags{ $_->{id} } for @tag_loop;
    }

    $min ||= 0;
    $max ||= 0;
    my $factor;
    if ( $max - $min == 0 ) {
        $min -= 6;
        $factor = 1;
    }
    else {
        $factor = 5 / log( $max - $min + 1 );
    }
    $factor *= ( $ntags / 6 ) if $ntags < 6;

    foreach my $tag (@tag_loop) {

        # now calc rank
        my $rank;
        my $count = $tag->{count};
        if ( $count - $min + 1 == 0 ) {
            $rank = 0;
        }
        else {
            $rank = 6 - int( log( $count - $min + 1 ) * $factor );
        }
        $tag->{rank} = $rank;
    }

    @tag_loop = sort { $a->{name} cmp $b->{name} } @tag_loop;
    $param->{tag_loop} = \@tag_loop;
} ## end sub mt_blog_stats_tag_cloud_tab

sub mt_blog_stats_widget_comment_tab {
    my ( $app, $tmpl, $param ) = @_;

    my $user    = $app->user;
    my $blog    = $app->blog;
    my $blog_id = $blog->id if $blog;

    $param->{editable} = $user->is_superuser;
    if ( $blog && !$param->{editable} ) {
        $param->{editable} = $user->permissions($blog_id)->can_edit_all_posts;
        $param->{comment_editable}
          = $user->permissions($blog_id)->can_manage_feedback;
    }

    my $comments = sub {
        my $args
          = { limit => 10, sort => 'created_on', direction => 'descend', };
        if ( !$user->is_superuser && !$blog_id ) {
            my $join_str = '= comment_blog_id';
            $args->{join} =
              MT::Permission->join_on(
                                       undef,
                                       {
                                          blog_id   => \$join_str,
                                          author_id => $user->id
                                       },
              );
        }
        my @c = MT::Comment->load( { (
                                         $blog_id
                                         ? ( blog_id => $blog_id )
                                         : ()
                                      ),
                                      junk_status => 1,
                                   },
                                   $args
        );
        \@c;
    };

    require MT::Promise;
    my $ctx = $tmpl->context;
    $ctx->stash( 'comments', MT::Promise::delay($comments) );
} ## end sub mt_blog_stats_widget_comment_tab

sub generate_dashboard_stats_comment_tab {
    my $app = shift;
    my ($tab) = @_;

    my $blog_id = $app->blog ? $app->blog->id : 0;
    my $user    = $app->user;
    my $user_id = $user->id;

    my $cmt_class = $app->model('comment');
    my $terms = { visible => 1 };
    $terms->{blog_id} = $blog_id if $blog_id;
    my $args = {
                 group => [
                            "extract(year from created_on)",
                            "extract(month from created_on)",
                            "extract(day from created_on)"
                 ],
    };

    require MT::Util;
    my @ts
      = MT::Util::offset_time_list( time - ( 121 * 24 * 60 * 60 ), $blog_id );
    my $earliest = sprintf( '%04d%02d%02d%02d%02d%02d',
                            $ts[5] + 1900,
                            $ts[4] + 1,
                            @ts[ 3, 2, 1, 0 ] );
    $terms->{created_on} = [ $earliest, undef ];
    $args->{range_incl}{created_on} = 1;

    if ( !$user->is_superuser && !$blog_id ) {
        my $join_str = '= comment_blog_id';
        $args->{join} =
          MT::Permission->join_on(
                                   undef,
                                   {
                                      blog_id   => \$join_str,
                                      author_id => $user_id
                                   },
          );
    }
    my $cmt_iter = $cmt_class->count_group_by( $terms, $args );

    my %counts;
    while ( my ( $count, $y, $m, $d ) = $cmt_iter->() ) {
        my $date = sprintf( "%04d%02d%02dT00:00:00", $y, $m, $d );
        $counts{$date} = $count;
    }

    %counts;
} ## end sub generate_dashboard_stats_comment_tab

sub melody_docs_widget {
    my $app = shift;
    my ($tmpl, $param) = @_;
    my $cache_duration = 60 * 60 * 24;
    my $session = MT::Session::get_unexpired_value($cache_duration, {
        id   => 'MELODY_DOCS_UPDATE',
        kind => 'MD'
    });
    
    if ( $session ) {
        $param->{news_items} = $session->data;
    } else {
        my $ua = MT->new_ua( { timeout => 10, max_size => 1000000000 } );

        my $req    = new HTTP::Request( GET => $app->config('DocNewsURL') );
        my $resp   = $ua->request($req);
        my $result = $resp->content();
        if ( $resp->is_success() && $result ) {
            use XML::Simple;            
            use File::Temp;
            use utf8;
            my $fh = File::Temp->new( UNLINK => 0 );
            my $xml;
            
            $fh->autoflush(1);
            print $fh $result;
            $fh->seek(0,0);
            $xml = XMLin($result, ForceArray => 1);
            close( $fh );
            
            my $entries = $xml->{entry};
            my @items;
            
            my $data = '';
            my $counter = 0;
            while ($counter < 5) {
                my $entry = $entries->[$counter];
                my $date = $entry->{published}->[0];
                my $author = $entry->{author}->[0]->{name}->[0];
                my $url = 'http://github.com' . $entry->{'link'}->[0]->{href};
                my $title = $entry->{title}->[0];

                $data .= '<ul>' if $entry == $entries->[0];
                $date = substr($date, 0, index($date, 'T'));
                $data .= sprintf('<li class="most-recent-entry"><div class="date">%s</div><a href="%s">%s updated %s</a></li>', $date, $url, $author, $title);
                
                $counter++;
            }
            $data .= '</ul>';

            $param->{news_items} = $data;
            
            $session = MT->model('session')->new();
            $session->id('MELODY_DOCS_UPDATE');
            $session->kind('MD');
            $session->data( $data );
            $session->start(time());
            $session->save() ||
                $app->log({
                    message => $app->translate('Could not update Melody documentation widget.')
                });
        }
    }

}

1;

__END__

=head1 NAME

MT::CMS::Dashboard

=head1 METHODS

=head2 create_dashboard_stats_file

=head2 create_stats_directory

=head2 dashboard

=head2 generate_dashboard_stats

=head2 generate_dashboard_stats_comment_tab

=head2 generate_dashboard_stats_entry_tab

=head2 get_lmt_content

=head2 get_newsbox_content

=head2 mt_blog_stats_tag_cloud_tab

=head2 mt_blog_stats_widget

=head2 mt_blog_stats_widget_comment_tab

=head2 mt_blog_stats_widget_entry_tab

=head2 melody_news_widget

=head2 new_version_widget

=head2 stats_generation_handler

=head2 this_is_you_widget


=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
