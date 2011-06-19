package MT::CMS::Entry;

use strict;
use MT::Util qw( format_ts relative_date remove_html encode_html encode_js
  encode_url archive_file_for offset_time_list );
use MT::I18N qw( substr_text const length_text wrap_text encode_text
  break_up_text first_n_text guess_encoding );

sub edit {
    my $cb = shift;
    my ( $app, $id, $obj, $param ) = @_;

    my $q          = $app->query;
    my $type       = $q->param('_type');
    my $perms      = $app->permissions;
    my $blog_class = $app->model('blog');
    my $blog       = $app->blog;
    my $blog_id    = $blog->id;
    my $author     = $app->user;
    my $class      = $app->model($type);

    # to trigger autosave logic in main edit routine
    $param->{autosave_support} = 1;

    my $original_revision;
    if ($id) {
        return $app->error( $app->translate("Invalid parameter") )
          if $obj->class ne $type;

        if ( $blog->use_revision ) {
            $original_revision = $obj->revision;
            my $rn = $q->param('r') || 0;
            if ( $rn != $obj->current_revision ) {
                my $status_text = MT::Entry::status_text( $obj->status );
                $param->{current_status_text} = $status_text;
                $param->{current_status_label}
                  = $app->translate($status_text);
                my $rev = $obj->load_revision( { rev_number => $rn } );
                if ( $rev && @$rev ) {
                    $obj = $rev->[0];
                    my $values = $obj->get_values;
                    $param->{$_} = $values->{$_} foreach keys %$values;
                    $param->{loaded_revision} = 1;
                }
                $param->{rev_number}       = $rn;
                $param->{no_snapshot}      = 1 if $q->param('no_snapshot');
                $param->{missing_cats_rev} = 1
                  if exists( $obj->{__missing_cats_rev} )
                      && $obj->{__missing_cats_rev};
                $param->{missing_tags_rev} = 1
                  if exists( $obj->{__missing_tags_rev} )
                      && $obj->{__missing_tags_rev};
            } ## end if ( $rn != $obj->current_revision)
            $param->{rev_date} =
              format_ts( "%Y-%m-%d %H:%M:%S",
                        $obj->modified_on, $blog,
                        $app->user ? $app->user->preferred_language : undef );
        } ## end if ( $blog->use_revision)

        $param->{nav_entries} = 1;
        $param->{entry_edit}  = 1;
        if ( $type eq 'entry' ) {
            $app->add_breadcrumb(
                                  $app->translate('Entries'),
                                  $app->uri(
                                             'mode' => 'list_entries',
                                             args   => { blog_id => $blog_id }
                                  )
            );
        }
        elsif ( $type eq 'page' ) {
            $app->add_breadcrumb(
                                  $app->translate('Pages'),
                                  $app->uri(
                                             'mode' => 'list_pages',
                                             args   => { blog_id => $blog_id }
                                  )
            );
        }
        $app->add_breadcrumb( $obj->title || $app->translate('(untitled)') );
        ## Don't pass in author_id, because it will clash with the
        ## author_id parameter of the author currently logged in.
        delete $param->{'author_id'};
        unless ( defined $q->param('category_id') ) {
            delete $param->{'category_id'};
            if ( my $cat = $obj->category ) {
                $param->{category_id} = $cat->id;
            }
        }
        $blog_id = $obj->blog_id;
        my $blog = $app->model('blog')->load($blog_id);
        my $status = $q->param('status') || $obj->status;
        $param->{ "status_" . MT::Entry::status_text($status) } = 1;
        if ( (
                  $obj->status == MT::Entry::JUNK()
               || $obj->status == MT::Entry::REVIEW()
             )
             && $obj->junk_log
          )
        {
            build_junk_table( $app, param => $param, object => $obj );
        }
        $param->{ "allow_comments_"
              . ( $q->param('allow_comments') || $obj->allow_comments || 0 ) }
          = 1;
        $param->{'authored_on_date'} = $q->param('authored_on_date')
          || format_ts( "%Y-%m-%d", $obj->authored_on, $blog,
                        $app->user ? $app->user->preferred_language : undef );
        $param->{'authored_on_time'} = $q->param('authored_on_time')
          || format_ts( "%H:%M:%S", $obj->authored_on, $blog,
                        $app->user ? $app->user->preferred_language : undef );

        $param->{num_comments} = $id ? $obj->comment_count : 0;
        $param->{num_pings}    = $id ? $obj->ping_count    : 0;

        # Check permission to send notifications and if the
        # blog has notification list subscribers
        if (    $perms->can_send_notifications
             && $obj->status == MT::Entry::RELEASE() )
        {
            my $not_class = $app->model('notification');
            $param->{can_send_notifications} = 1;
            $param->{has_subscribers}
              = $not_class->exist( { blog_id => $blog_id } );
        }

        ## Load next and previous entries for next/previous links
        if ( my $next = $obj->next ) {
            $param->{next_entry_id} = $next->id;
        }
        if ( my $prev = $obj->previous ) {
            $param->{previous_entry_id} = $prev->id;
        }

        $param->{has_any_pinged_urls} = ( $obj->pinged_urls || '' ) =~ m/\S/;
        $param->{ping_errors}         = $q->param('ping_errors');
        $param->{can_view_log}        = $app->user->can_view_log;
        $param->{entry_permalink}     = $obj->permalink;
        $param->{'mode_view_entry'}   = 1;
        $param->{'basename_old'}      = $obj->basename;

        if ( my $ts = $obj->authored_on ) {
            $param->{authored_on_ts} = $ts;
            $param->{authored_on_formatted}
              = format_ts(
                           MT::App::CMS::LISTING_DATETIME_FORMAT(),
                           $ts,
                           $blog,
                           $app->user ? $app->user->preferred_language : undef
              );
        }

        $app->load_list_actions( $type, $param );
    } ## end if ($id)
    else {
        $param->{entry_edit} = 1;
        if ($blog_id) {
            if ( $type eq 'entry' ) {
                $app->add_breadcrumb(
                                      $app->translate('Entries'),
                                      $app->uri(
                                               'mode' => 'list_entries',
                                               args => { blog_id => $blog_id }
                                      )
                );
                $app->add_breadcrumb( $app->translate('New Entry') );
                $param->{nav_new_entry} = 1;
            }
            elsif ( $type eq 'page' ) {
                $app->add_breadcrumb(
                                      $app->translate('Pages'),
                                      $app->uri(
                                               'mode' => 'list_pages',
                                               args => { blog_id => $blog_id }
                                      )
                );
                $app->add_breadcrumb( $app->translate('New Page') );
                $param->{nav_new_page} = 1;
            }
        } ## end if ($blog_id)

        # (if there is no blog_id parameter, this is a
        # bookmarklet post and doesn't need breadcrumbs.)
        delete $param->{'author_id'};
        delete $param->{'pinged_urls'};
        my $blog_timezone = 0;
        if ($blog_id) {
            my $blog = $blog_class->load($blog_id)
              or return $app->error(
                     $app->translate( 'Can\'t load blog #[_1].', $blog_id ) );
            $blog_timezone = $blog->server_offset();

            # new entry defaults used for new entries AND new pages.
            my $def_status = $q->param('status') || $blog->status_default;
            if ($def_status) {
                $param->{ "status_" . MT::Entry::status_text($def_status) }
                  = 1;
            }
            if ( $param->{status} ) {
                $param->{ 'allow_comments_' . $q->param('allow_comments') }
                  = 1;
                $param->{allow_comments} = $q->param('allow_comments');
                $param->{allow_pings}    = $q->param('allow_pings');
            }
            else {

                # new edit
                $param->{ 'allow_comments_' . $blog->allow_comments_default }
                  = 1;
                $param->{allow_comments} = $blog->allow_comments_default;
                $param->{allow_pings}    = $blog->allow_pings_default;
            }
        } ## end if ($blog_id)

        require POSIX;
        my @now = offset_time_list( time, $blog );
        $param->{authored_on_date} = $q->param('authored_on_date')
          || POSIX::strftime( "%Y-%m-%d", @now );
        $param->{authored_on_time} = $q->param('authored_on_time')
          || POSIX::strftime( "%H:%M:%S", @now );
    } ## end else [ if ($id) ]

    ## show the necessary associated assets
    if ( $type eq 'entry' || $type eq 'page' ) {
        require MT::Asset;
        require MT::ObjectAsset;
        my $assets = ();
        if ( $q->param('reedit') && $q->param('include_asset_ids') ) {
            my $include_asset_ids = $q->param('include_asset_ids');
            my @asset_ids = split( ',', $include_asset_ids );
            foreach my $asset_id (@asset_ids) {
                my $asset = MT::Asset->load($asset_id);
                if ($asset) {
                    my $asset_1;
                    if ( $asset->class eq 'image' ) {
                        $asset_1 = {
                                     asset_id   => $asset->id,
                                     asset_name => $asset->file_name,
                                     asset_thumb =>
                                       $asset->thumbnail_url( Width => 100 )
                        };
                    }
                    else {
                        $asset_1 = {
                                     asset_id   => $asset->id,
                                     asset_name => $asset->file_name
                        };
                    }
                    push @{$assets}, $asset_1;
                }
            } ## end foreach my $asset_id (@asset_ids)
        } ## end if ( $q->param('reedit'...))
        elsif ( $q->param('asset_id') && !$id ) {
            my $asset = MT::Asset->load( $q->param('asset_id') );
            my $asset_1
              = { asset_id => $asset->id, asset_name => $asset->file_name };
            push @{$assets}, $asset_1;
        }
        elsif ($id) {
            my $join_str = '= asset_id';
            my @assets =
              MT::Asset->load(
                               { class => '*' },
                               {
                                  join =>
                                    MT::ObjectAsset->join_on(
                                                    undef,
                                                    {
                                                      asset_id  => \$join_str,
                                                      object_ds => 'entry',
                                                      object_id => $id
                                                    }
                                    )
                               }
              );
            foreach my $asset (@assets) {
                my $asset_1;
                if ( $asset->class eq 'image' ) {
                    $asset_1 = {
                          asset_id    => $asset->id,
                          asset_name  => $asset->file_name,
                          asset_thumb => $asset->thumbnail_url( Width => 100 )
                    };
                }
                else {
                    $asset_1 = {
                                 asset_id   => $asset->id,
                                 asset_name => $asset->file_name
                    };
                }
                push @{$assets}, $asset_1;
            }
        } ## end elsif ($id)
        $param->{asset_loop} = $assets;
    } ## end if ( $type eq 'entry' ...)

    ## Load categories and process into loop for category pull-down.
    require MT::Placement;
    my $cat_id = $param->{category_id};
    my $depth  = 0;
    my %places;

    # set the dirty flag in js?
    $param->{dirty} = $q->param('dirty') ? 1 : 0;

    if ($id) {
        my @places
          = MT::Placement->load( { entry_id => $id, is_primary => 0 } );
        %places = map { $_->category_id => 1 } @places;
    }
    my $cats = $q->param('category_ids');
    if ( defined $cats ) {
        if ( my @cats = grep { $_ =~ /^\d+/ } split( /,/, $cats ) ) {
            $cat_id = $cats[0];
            %places = map { $_ => 1 } @cats;
        }
    }
    if ( $q->param('reedit') ) {
        $param->{reedit} = 1;
        if ( !$q->param('basename_manual') ) {
            $param->{'basename'} = '';
        }
        $param->{'revision-note'} = $q->param('revision-note');
        if ( $q->param('save_revision') ) {
            $param->{'save_revision'} = 1;
        }
        else {
            $param->{'save_revision'} = 0;
        }
    }
    if ($blog) {
        $param->{file_extension} = $blog->file_extension || '';
        $param->{file_extension} = '.' . $param->{file_extension}
          if $param->{file_extension} ne '';
    }
    else {
        $param->{file_extension} = 'html';
    }

    ## Now load user's preferences and customization for new/edit
    ## entry page.
    if ($perms) {
        my $pref_param = $app->load_entry_prefs( $perms->entry_prefs );
        %$param = ( %$param, %$pref_param );
        $param->{disp_prefs_bar_colspan} = $param->{new_object} ? 1 : 2;

        # Completion for tags
        my $auth_prefs = $author->entry_prefs;
        if ( my $delim = chr( $auth_prefs->{tag_delim} ) ) {
            if ( $delim eq ',' ) {
                $param->{'auth_pref_tag_delim_comma'} = 1;
            }
            elsif ( $delim eq ' ' ) {
                $param->{'auth_pref_tag_delim_space'} = 1;
            }
            else {
                $param->{'auth_pref_tag_delim_other'} = 1;
            }
            $param->{'auth_pref_tag_delim'} = $delim;
        }

        my $tags_js = MT::Util::to_json(
                                         MT::Tag->cache(
                                                         blog_id => $blog_id,
                                                         class => 'MT::Entry',
                                                         private => 1
                                         )
        );
        $tags_js =~ s!/!\\/!g;
        $param->{tags_js} = $tags_js;

        $param->{can_edit_categories} = $perms->can_edit_categories;
    } ## end if ($perms)

    my $data =
      $app->_build_category_list(
                                  blog_id => $blog_id,
                                  markers => 1,
                                  type    => $class->container_type,
      );
    my $top_cat = $cat_id;
    my @sel_cats;
    my $cat_tree = [];
    if ( $type eq 'page' ) {
        push @$cat_tree,
          { id => -1, label => '/', basename => '/', path => [], };
        $top_cat ||= -1;
    }
    foreach (@$data) {
        next unless exists $_->{category_id};
        if ( $type eq 'page' ) {
            $_->{category_path_ids} ||= [];
            unshift @{ $_->{category_path_ids} }, -1;
        }
        push @$cat_tree,
          {
            id       => $_->{category_id},
            label    => $_->{category_label} . ( $type eq 'page' ? '/' : '' ),
            basename => $_->{category_basename}
              . ( $type eq 'page' ? '/' : '' ),
            path => $_->{category_path_ids} || [],
          };
        push @sel_cats, $_->{category_id}
          if $places{ $_->{category_id} } && $_->{category_id} != $cat_id;
    }
    $param->{category_tree} = $cat_tree;
    unshift @sel_cats, $top_cat if defined $top_cat && $top_cat ne "";
    $param->{selected_category_loop}   = \@sel_cats;
    $param->{have_multiple_categories} = scalar @$data > 1;

    $param->{basename_limit} = ( $blog ? $blog->basename_limit : 0 ) || 30;

    if ( $q->param('tags') ) {
        $param->{tags} = $q->param('tags');
    }
    else {
        if ($obj) {
            my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
            require MT::Tag;
            my $tags = MT::Tag->join( $tag_delim, $obj->tags );
            $param->{tags} = $tags;
        }
    }

    ## Load text filters if user displays them
    my %entry_filters;
    if ( defined( my $filter = $q->param('convert_breaks') ) ) {
        my @filters = split( /\s*,\s*/, $filter );
        $entry_filters{$_} = 1 for @filters;
    }
    elsif ($obj) {
        %entry_filters = map { $_ => 1 } @{ $obj->text_filters };
    }
    elsif ($blog) {
        my $cb = $author->text_format || $blog->convert_paras;
        $cb = '__default__' if $cb eq '1';
        $entry_filters{$cb} = 1;
        $param->{convert_breaks} = $cb;
    }
    my $filters = MT->all_text_filters;
    $param->{text_filters} = [];
    for my $filter ( keys %$filters ) {
        if ( my $cond = $filters->{$filter}{condition} ) {
            $cond = MT->handler_to_coderef($cond) if !ref($cond);
            next unless $cond->($type);
        }
        push @{ $param->{text_filters} },
          {
            filter_key      => $filter,
            filter_label    => $filters->{$filter}{label},
            filter_selected => $entry_filters{$filter},
            filter_docs     => $filters->{$filter}{docs},
          };
    }
    $param->{text_filters} = [ sort { $a->{filter_key} cmp $b->{filter_key} }
                               @{ $param->{text_filters} } ];
    unshift @{ $param->{text_filters} },
      {
        filter_key      => '0',
        filter_label    => $app->translate('None'),
        filter_selected => ( !keys %entry_filters ),
      };

    if ($blog) {
        if ( !defined $param->{convert_breaks} ) {
            my $cb = $blog->convert_paras;
            $cb = '__default__' if $cb eq '1';
            $param->{convert_breaks} = $cb;
        }
        my $ext = ( $blog->file_extension || '' );
        $ext = '.' . $ext if $ext ne '';
        $param->{blog_file_extension} = $ext;
    }

    my $rte      = lc( $app->config('RichTextEditor') );
    my $editors  = $app->registry("richtext_editors");
    my $edit_reg = $editors->{$rte};
    if ( my $rte_tmpl
         = $edit_reg->{plugin}->load_tmpl( $edit_reg->{template} ) )
    {
        $param->{rich_editor}      = $rte;
        $param->{rich_editor_tmpl} = $rte_tmpl;
    }

    my $perms = $app->user->permissions;
    require JSON;
    my $user_prefs = JSON::from_json($perms->ui_prefs);
    my @fields = ( $user_prefs->{entry_field_order} ? 
        split(',',$user_prefs->{entry_field_order})
        : qw( title text tags excerpt keywords ) );
    $param->{object_type}  = $type;
    $param->{object_label} = $class->class_label;
    $param->{field_loop} ||= [
        map { {
               field_name => $_,
               field_id   => $_,
               lock_field => ( $_ eq 'title' or $_ eq 'text' ),
               show_field => ( $_ eq 'title' or $_ eq 'text' )
               ? 1
               : $param->{"disp_prefs_show_$_"},
               field_label => $app->translate( ucfirst($_) ),
            }
          } @fields
    ];
    $param->{quickpost_js} = MT::CMS::Entry::quickpost_js( $app, $type );
    if ( 'page' eq $type ) {
        $param->{search_label} = $app->translate('pages');
        $param->{output}       = 'edit_entry.tmpl';
        $param->{screen_class} = 'edit-page edit-entry';
    }
    $param->{sitepath_configured} = $blog && $blog->site_path ? 1 : 0;
    if ( $blog->use_revision ) {
        $param->{use_revision} = 1;

        #TODO: the list of revisions won't appear on the edit screen.
        #    $param->{revision_table} = $app->build_page(
        #        MT::CMS::Common::build_revision_table(
        #            $app,
        #            object => $obj || $class->new,
        #            param => {
        #                template => 'include/revision_table.tmpl',
        #                args     => {
        #                    sort_order => 'rev_number',
        #                    direction  => 'descend',
        #                    limit      => 5,              # TODO: configurable?
        #                },
        #                revision => $original_revision
        #                  ? $original_revision
        #                  : $obj
        #                    ? $obj->revision || $obj->current_revision
        #                    : 0,
        #            }
        #        ),
        #        { show_actions => 0, hide_pager => 1 }
        #    );
    } ## end if ( $blog->use_revision)
    1;
} ## end sub edit

sub build_junk_table {
    my $app = shift;
    my (%args) = @_;

    my $param = $args{param};
    my $obj   = $args{object};

    # if ( defined $obj->junk_score ) {
    #     $param->{junk_score} =
    #       ( $obj->junk_score > 0 ? '+' : '' ) . $obj->junk_score;
    # }
    my $log = $obj->junk_log || '';
    my @log = split( /\r?\n/, $log );
    my @junk;
    for ( my $i = 0; $i < scalar(@log); $i++ ) {
        my $line = $log[$i];
        $line =~ s/(^\s+|\s+$)//g;
        next unless $line;
        last if $line =~ m/^--->/;
        my ( $test, $score, $log );
        ($test) = $line =~ m/^([^:]+?):/;
        if ( defined $test ) {
            ($score) = $test =~ m/\(([+-]?\d+?(?:\.\d*?)?)\)/;
            $test =~ s/\(.+\)//;
        }
        if ( defined $score ) {
            $score =~ s/\+//;
            $score .= '.0' unless $score =~ m/\./;
            $score = ( $score > 0 ? '+' : '' ) . $score;
        }
        $log = $line;
        $log =~ s/^[^:]+:\s*//;
        $log = encode_html($log);
        for ( my $j = $i + 1; $j < scalar(@log); $j++ ) {
            my $line = encode_html( $log[$j] );
            if ( $line =~ m/^\t+(.*)$/s ) {
                $i = $j;
                $log .= "<br />" . $1;
            }
            else {
                last;
            }
        }
        push @junk, { test => $test, score => $score, log => $log };
    } ## end for ( my $i = 0; $i < scalar...)
    $param->{junk_log_loop} = \@junk;
    \@junk;
} ## end sub build_junk_table

sub preview {
    my $app         = shift;
    my $q           = $app->query;
    my $type        = $q->param('_type') || 'entry';
    my $entry_class = $app->model($type);
    my $blog_id     = $q->param('blog_id');
    my $blog        = $app->blog;
    my $id          = $q->param('id');
    my $entry;
    my $user_id = $app->user->id;

    if ($id) {
        $entry = $entry_class->load( { id => $id, blog_id => $blog_id } )
          or return $app->errtrans("Invalid request.");
        $user_id = $entry->author_id;
    }
    else {
        $entry = $entry_class->new;
        $entry->author_id($user_id);
        $entry->id(-1);    # fake out things like MT::Taggable::__load_tags
        $entry->blog_id($blog_id);
    }
    my $cat;
    my $names = $entry->column_names;

    my %values = map { $_ => scalar $q->param($_) } @$names;
    delete $values{'id'} unless $q->param('id');
    ## Strip linefeed characters.
    for my $col (qw( text excerpt text_more keywords )) {
        $values{$col} =~ tr/\r//d if $values{$col};
    }
    $values{allow_comments} = 0
      if !defined( $values{allow_comments} )
          || $q->param('allow_comments') eq '';
    $values{allow_pings} = 0
      if !defined( $values{allow_pings} ) || $q->param('allow_pings') eq '';
    $entry->set_values( \%values );

    my $cat_ids = $q->param('category_ids');
    if ($cat_ids) {
        my @cats = split( /,/, $cat_ids );
        if (@cats) {
            my $primary_cat = $cats[0];
            $cat = MT::Category->load(
                                { id => $primary_cat, blog_id => $blog_id } );
            my @categories
              = MT::Category->load( { id => \@cats, blog_id => $blog_id } );
            $entry->cache_property( 'category',   undef, $cat );
            $entry->cache_property( 'categories', undef, \@categories );
        }
    }
    else {
        $entry->cache_property( 'category', undef, undef );
        $entry->cache_property( 'categories', undef, [] );
    }
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tag_names = MT::Tag->split( $tag_delim, $q->param('tags') );
    if (@tag_names) {
        my @tags;
        foreach my $tag_name (@tag_names) {
            next if $tag_name =~ m/^@/;
            my $tag = MT::Tag->new;
            $tag->name($tag_name);
            push @tags, $tag;
        }
        $entry->{__tags}        = \@tag_names;
        $entry->{__tag_objects} = \@tags;
    }

    my $date = $q->param('authored_on_date');
    my $time = $q->param('authored_on_time');
    my $ts   = $date . $time;
    $ts =~ s/\D//g;
    $entry->authored_on($ts);

    my $preview_basename = $app->preview_object_basename;
    $entry->basename($preview_basename);

    require MT::TemplateMap;
    require MT::Template;
    my $tmpl_map =
      MT::TemplateMap->load( {
                 archive_type => ( $type eq 'page' ? 'Page' : 'Individual' ),
                 is_preferred => 1,
                 blog_id      => $blog_id,
               }
      );

    my $tmpl;
    my $fullscreen;
    my $archive_file;
    my $orig_file;
    my $file_ext;
    if ($tmpl_map) {
        $tmpl         = MT::Template->load( $tmpl_map->template_id );
        $file_ext     = $blog->file_extension || '';
        $archive_file = $entry->archive_file;

        my $blog_path
          = $type eq 'page'
          ? $blog->site_path
          : ( $blog->archive_path || $blog->site_path );
        $archive_file = File::Spec->catfile( $blog_path, $archive_file );
        require File::Basename;
        my $path;
        ( $orig_file, $path ) = File::Basename::fileparse($archive_file);
        $file_ext = '.' . $file_ext if $file_ext ne '';
        $archive_file
          = File::Spec->catfile( $path, $preview_basename . $file_ext );
    }
    else {
        $tmpl       = $app->load_tmpl('preview_entry_content.tmpl');
        $fullscreen = 1;
    }
    return $app->error( $app->translate('Can\'t load template.') )
      unless $tmpl;

    # translates naughty words when PublishCharset is NOT UTF-8
    MT::Util::translate_naughty_words($entry);

    $entry->convert_breaks( scalar $q->param('convert_breaks') );

    my @data = ( { data_name => 'author_id', data_value => $user_id } );
    $app->run_callbacks( 'cms_pre_preview', $app, $entry, \@data );

    my $ctx = $tmpl->context;
    $ctx->stash( 'entry',    $entry );
    $ctx->stash( 'blog',     $blog );
    $ctx->stash( 'category', $cat ) if $cat;
    $ctx->{current_timestamp} = $ts;
    $ctx->var( 'entry_template',    1 );
    $ctx->var( 'archive_template',  1 );
    $ctx->var( 'entry_template',    1 );
    $ctx->var( 'feedback_template', 1 );
    $ctx->var( 'archive_class',     'entry-archive' );
    $ctx->var( 'preview_template',  1 );
    my $html = $tmpl->output;
    my %param;

    unless ( defined($html) ) {
        my $preview_error = $app->translate( "Publish error: [_1]",
                                     MT::Util::encode_html( $tmpl->errstr ) );
        $param{preview_error} = $preview_error;
        my $tmpl_plain = $app->load_tmpl('preview_entry_content.tmpl');
        $tmpl->text( $tmpl_plain->text );
        $html = $tmpl->output;
        defined($html)
          or return $app->error(
                    $app->translate( "Publish error: [_1]", $tmpl->errstr ) );
        $fullscreen = 1;
    }

    # If MT is configured to do 'local' previews, convert all
    # the normal blog URLs into the domain used by MT itself (ie,
    # blog is published to www.example.com, which is a different
    # server from where MT runs, mt.example.com; previews therefore
    # should occur locally, so replace all http://www.example.com/
    # with http://mt.example.com/).
    my ( $old_url, $new_url );
    if ( $app->config('LocalPreviews') ) {
        $old_url = $blog->site_url;
        $old_url =~ s!^(https?://[^/]+?/)(.*)?!$1!;
        $new_url = $app->base . '/';
        $html =~ s!\Q$old_url\E!$new_url!g;
    }

    if ( !$fullscreen ) {
        my $fmgr = $blog->file_mgr;

        ## Determine if we need to build directory structure,
        ## and build it if we do. DirUmask determines
        ## directory permissions.
        require File::Basename;
        my $path = File::Basename::dirname($archive_file);
        $path =~ s!/$!!
          unless $path eq '/';   ## OS X doesn't like / at the end in mkdir().
        unless ( $fmgr->exists($path) ) {
            $fmgr->mkpath($path);
        }

        if ( $fmgr->exists($path) && $fmgr->can_write($path) ) {
            $fmgr->put_data( $html, $archive_file );
            $param{preview_file} = $preview_basename;
            my $preview_url = $entry->archive_url;
            $preview_url
              =~ s! / \Q$orig_file\E ( /? ) $!/$preview_basename$file_ext$1!x;

            # We also have to translate the URL used for the
            # published file to be on the MT app domain.
            if ( defined $new_url ) {
                $preview_url =~ s!^\Q$old_url\E!$new_url!;
            }

            $param{preview_url} = $preview_url;

            # we have to make a record of this preview just in case it
            # isn't cleaned up by re-editing, saving or cancelling on
            # by the user.
            require MT::Session;
            my $sess_obj = MT::Session->get_by_key( {
                  id   => $preview_basename,
                  kind => 'TF',                # TF = Temporary File
                  name => $archive_file,
                }
            );
            $sess_obj->start(time);
            $sess_obj->save;
        } ## end if ( $fmgr->exists($path...))
        else {
            $fullscreen = 1;
            $param{preview_error} =
              $app->translate(
                       "Unable to create preview file in this location: [_1]",
                       $path );
            my $tmpl_plain = $app->load_tmpl('preview_entry_content.tmpl');
            $tmpl->text( $tmpl_plain->text );
            $tmpl->reset_tokens;
            $html = $tmpl->output;
            $param{preview_body} = $html;
        }
    } ## end if ( !$fullscreen )
    else {
        $param{preview_body} = $html;
    }
    $param{id} = $id if $id;
    $param{new_object} = $param{id} ? 0 : 1;
    $param{title} = $entry->title;
    my $cols = $entry_class->column_names;

    for my $col (@$cols) {
        next
          if $col eq 'created_on'
              || $col eq 'created_by'
              || $col eq 'modified_on'
              || $col eq 'modified_by'
              || $col eq 'authored_on'
              || $col eq 'author_id'
              || $col eq 'pinged_urls'
              || $col eq 'tangent_cache'
              || $col eq 'template_id'
              || $col eq 'class'
              || $col eq 'meta'
              || $col eq 'comment_count'
              || $col eq 'ping_count'
              || $col eq 'current_revision';
        push @data,
          { data_name => $col, data_value => scalar $q->param($col) };
    }
    for my $data (
        qw( authored_on_date authored_on_time basename_manual basename_old category_ids tags include_asset_ids save_revision revision-note )
      )
    {
        push @data,
          { data_name => $data, data_value => scalar $q->param($data) };
    }

    $param{entry_loop} = \@data;
    my $list_mode;
    my $list_title;
    if ( $type eq 'page' ) {
        $list_title = 'Pages';
        $list_mode  = 'list_pages';
    }
    else {
        $list_title = 'Entries';
        $list_mode  = 'list_entries';
    }
    if ($id) {
        $app->add_breadcrumb(
                              $app->translate($list_title),
                              $app->uri(
                                         'mode' => $list_mode,
                                         args   => { blog_id => $blog_id }
                              )
        );
        $app->add_breadcrumb(    $entry->title
                              || $app->translate('(untitled)') );
    }
    else {
        $app->add_breadcrumb(
                              $app->translate($list_title),
                              $app->uri(
                                         'mode' => $list_mode,
                                         args   => { blog_id => $blog_id }
                              )
        );
        $app->add_breadcrumb(
                   $app->translate( 'New [_1]', $entry_class->class_label ) );
        $param{nav_new_entry} = 1;
    }
    $param{object_type}  = $type;
    $param{object_label} = $entry_class->class_label;

    $param{diff_view} = $q->param('rev_numbers') || $q->param('collision');
    $param{collision} = 1;
    if ( my @rev_numbers = split( /,/, $q->param('rev_numbers') ) ) {
        $param{comparing_revisions} = 1;
        $param{rev_a}               = $rev_numbers[0];
        $param{rev_b}               = $rev_numbers[1];
    }
    $param{dirty} = $q->param('dirty') ? 1 : 0;


    if ($fullscreen) {
        return $app->load_tmpl( 'preview_entry.tmpl', \%param );
    }
    else {
        $app->request( 'preview_object', $entry );
        return $app->load_tmpl( 'preview_strip.tmpl', \%param );
    }
} ## end sub preview

sub save {
    my $app = shift;
    my $q   = $app->query;
    $app->validate_magic or return;
    $app->remove_preview_file;
    if ( $q->param('is_power_edit') ) {
        return $app->save_entries(@_);
    }
    my $author = $app->user;
    my $type = $q->param('_type') || 'entry';

    my $class = $app->model($type)
      or return $app->errtrans("Invalid parameter");

    my $cat_class = $app->model( $class->container_type );

    my $perms = $app->permissions
      or return $app->errtrans("Permission denied.");

    if ( $type eq 'page' ) {
        return $app->errtrans("Permission denied.")
          unless $perms->can_manage_pages;
    }

    my $id = $q->param('id');
    if ( !$id ) {
        return $app->errtrans("Permission denied.")
          unless ( ( 'entry' eq $type ) && $perms->can_create_post )
          || ( ( 'page' eq $type ) && $perms->can_manage_pages );
    }

    # check for autosave
    if ( $q->param('_autosave') ) {
        return $app->autosave_object();
    }

    require MT::Blog;
    my $blog_id = $q->param('blog_id');
    my $blog    = MT::Blog->load($blog_id)
      or return $app->error(
                     $app->translate( 'Can\'t load blog #[_1].', $blog_id ) );

    my $archive_type;

    my ( $obj, $orig_obj, $orig_file );
    if ($id) {
        $obj = $class->load($id)
          || return $app->error(
                    $app->translate( "No such [_1].", $class->class_label ) );
        return $app->error( $app->translate("Invalid parameter") )
          unless $obj->blog_id == $blog_id;
        if ( $type eq 'entry' ) {
            return $app->error( $app->translate("Permission denied.") )
              unless $perms->can_edit_entry( $obj, $author );
            return $app->error( $app->translate("Permission denied.") )
              if ( $obj->status ne $q->param('status') )
              && !( $perms->can_edit_entry( $obj, $author, 1 ) );
            $archive_type = 'Individual';
        }
        elsif ( $type eq 'page' ) {
            $archive_type = 'Page';
        }
        $orig_obj = $obj->clone;
        $orig_file = archive_file_for( $orig_obj, $blog, $archive_type );
    } ## end if ($id)
    else {
        $obj = $class->new;
    }
    my $status_old = $id ? $obj->status : 0;
    my $names = $obj->column_names;

    ## Get rid of category_id param, because we don't want to just set it
    ## in the Entry record; save it for later when we will set the Placement.
    my ( $cat_id, @add_cat )
      = split( /\s*,\s*/, ( $q->param('category_ids') || '' ) );
    $app->delete_param('category_id');
    if ($id) {
        ## Delete the author_id param (if present), because we don't want to
        ## change the existing author.
        $app->delete_param('author_id');
    }

    my %values = map { $_ => scalar $q->param($_) } @$names;
    delete $values{'id'} unless $q->param('id');
    ## Strip linefeed characters.
    for my $col (qw( text excerpt text_more keywords )) {
        $values{$col} =~ tr/\r//d if $values{$col};
    }
    $values{allow_comments} = 0
      if !defined( $values{allow_comments} )
          || $q->param('allow_comments') eq '';
    delete $values{week_number} if ( $q->param('week_number') || '' ) eq '';
    delete $values{basename}
      unless $perms->can_publish_post || $perms->can_edit_all_posts;
    $obj->set_values( \%values );
    $obj->allow_pings(0)
      if !defined $q->param('allow_pings') || $q->param('allow_pings') eq '';
    my $ao_d = $q->param('authored_on_date');
    my $ao_t = $q->param('authored_on_time');

    if ( !$id ) {

        #  basename check for this new entry...
        if (    ( my $basename = $q->param('basename') )
             && !$q->param('basename_manual')
             && $type eq 'entry' )
        {
            my $exist = $class->exist(
                             { blog_id => $blog_id, basename => $basename } );
            if ($exist) {
                $obj->basename( MT::Util::make_unique_basename($obj) );
            }
        }
    }

    if ( $type eq 'page' ) {

        # -1 is a special id for identifying the 'root' folder
        $cat_id = 0 if $cat_id == -1;
        my $dup_it = $class->load_iter( {
                                       blog_id  => $blog_id,
                                       basename => $obj->basename,
                                       class    => 'page',
                                       ( $id ? ( id => $id ) : () )
                                     },
                                     { ( $id ? ( not => { id => 1 } ) : () ) }
        );
        while ( my $p = $dup_it->() ) {
            my $p_folder = $p->folder;
            my $dup_folder_path
              = defined $p_folder ? $p_folder->publish_path() : '';
            my $folder = MT::Folder->load($cat_id) if $cat_id;
            my $folder_path = defined $folder ? $folder->publish_path() : '';
            return
              $app->error(
                $app->translate(
                    "Same Basename has already been used. You should use an unique basename."
                )
              ) if ( $dup_folder_path eq $folder_path );
        }

    } ## end if ( $type eq 'page' )

    if ( $type eq 'entry' ) {
        $obj->status( MT::Entry::HOLD() )
          if !$id && !$perms->can_publish_post && !$perms->can_edit_all_posts;
    }

    my $filter_result
      = $app->run_callbacks( 'cms_save_filter.' . $type, $app );

    if ( !$filter_result ) {
        my %param = ();
        $param{error}       = $app->errstr;
        $param{return_args} = $q->param('return_args');
        return $app->forward( "view", \%param );
    }

    # check to make sure blog has site url and path defined.
    # otherwise, we can't publish a released entry
    if ( ( $obj->status || 0 ) != MT::Entry::HOLD() ) {
        if ( !$blog->site_path || !$blog->site_url ) {
            return
              $app->error(
                $app->translate(
                    "Your blog has not been configured with a site path and URL. You cannot publish entries until these are defined."
                )
              );
        }
    }

    my ( $previous_old, $next_old );
    if (    ( $perms->can_publish_post || $perms->can_edit_all_posts )
         && ($ao_d) )
    {
        my %param = ();
        my $ao    = $ao_d . ' ' . $ao_t;
        unless ( $ao
            =~ m!^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$!
          )
        {
            $param{error} =
              $app->translate(
                "Invalid date '[_1]'; authored on dates must be in the format YYYY-MM-DD HH:MM:SS.",
                $ao
              );
        }
        my $s = $6 || 0;
        $param{error}
          = $app->translate(
               "Invalid date '[_1]'; authored on dates should be real dates.",
               $ao )
          if (
                  $s > 59
               || $s < 0
               || $5 > 59
               || $5 < 0
               || $4 > 23
               || $4 < 0
               || $2 > 12
               || $2 < 1
               || $3 < 1
               || ( MT::Util::days_in( $2, $1 ) < $3
                    && !MT::Util::leap_day( $0, $1, $2 ) )
          );
        $param{return_args} = $q->param('return_args');
        return $app->forward( "view", \%param ) if $param{error};
        if ( $obj->authored_on ) {
            $previous_old = $obj->previous(1);
            $next_old     = $obj->next(1);
        }
        my $ts = sprintf "%04d%02d%02d%02d%02d%02d", $1, $2, $3, $4, $5, $s;
        $obj->authored_on($ts);
    } ## end if ( ( $perms->can_publish_post...))
    my $is_new = $obj->id ? 0 : 1;

    MT::Util::translate_naughty_words($obj);

    $app->run_callbacks( 'cms_pre_save.' . $type, $app, $obj, $orig_obj )
      || return
      $app->error(
             $app->translate(
                              "Saving [_1] failed: [_2]", $class->class_label,
                              $app->errstr
             )
      );

    # Setting modified_by updates modified_on which we want to do before
    # a save but after pre_save callbacks fire.
    $obj->modified_by( $author->id ) unless $is_new;

    $obj->save
      or return
      $app->error(
             $app->translate(
                              "Saving [_1] failed: [_2]", $class->class_label,
                              $obj->errstr
             )
      );

    ## look if any assets have been included/removed from this entry
    require MT::Asset;
    require MT::ObjectAsset;
    my $include_asset_ids = $q->param('include_asset_ids') || '';
    my @asset_ids = split( ',', $include_asset_ids );
    my $obj_assets = ();
    my @obj_assets = MT::ObjectAsset->load(
                            { object_ds => 'entry', object_id => $obj->id } );
    foreach my $obj_asset (@obj_assets) {
        my $asset_id = $obj_asset->asset_id;
        $obj_assets->{$asset_id} = 1;
    }
    my $seen = ();
    foreach my $asset_id (@asset_ids) {
        my $asset = MT->model('asset')->load($asset_id);
        unless ( $asset->is_associated($obj) ) {
            $asset->associate( $obj, 0 );
        }
        $seen->{$asset_id} = 1;
    }
    foreach my $asset_id ( keys %{$obj_assets} ) {
        my $asset = MT->model('asset')->load($asset_id);
        unless ( $seen->{$asset_id} ) {
            $asset->unassociate($obj);
        }
    }

    my $message;
    if ($is_new) {
        $message
          = $app->translate( "[_1] '[_2]' (ID:[_3]) added by user '[_4]'",
                             $class->class_label, $obj->title, $obj->id,
                             $author->name );
    }
    elsif ( $orig_obj->status ne $obj->status ) {
        $message = $app->translate(
            "[_1] '[_2]' (ID:[_3]) edited and its status changed from [_4] to [_5] by user '[_6]'",
            $class->class_label,
            $obj->title,
            $obj->id,
            $app->translate( MT::Entry::status_text( $orig_obj->status ) ),
            $app->translate( MT::Entry::status_text( $obj->status ) ),
            $author->name
        );

    }
    else {
        $message
          = $app->translate( "[_1] '[_2]' (ID:[_3]) edited by user '[_4]'",
                             $class->class_label, $obj->title, $obj->id,
                             $author->name );
    }
    require MT::Log;
    $app->log( {
                 message => $message,
                 level   => MT::Log::INFO(),
                 class   => $type,
                 $is_new ? ( category => 'new' ) : ( category => 'edit' ),
                 metadata => $obj->id
               }
    );

    my $error_string = MT::callback_errstr();

    ## Now that the object is saved, we can be certain that it has an
    ## ID. So we can now add/update/remove the primary placement.
    require MT::Placement;
    my $place
      = MT::Placement->load( { entry_id => $obj->id, is_primary => 1 } );
    if ($cat_id) {
        unless ($place) {
            $place = MT::Placement->new;
            $place->entry_id( $obj->id );
            $place->blog_id( $obj->blog_id );
            $place->is_primary(1);
        }
        $place->category_id($cat_id);
        $place->save;
        my $cat = $cat_class->load($cat_id);
        $obj->cache_property( 'category', undef, $cat );
    }
    else {
        if ($place) {
            $place->remove;
            $obj->cache_property( 'category', undef, undef );
        }
    }

    my $placements_updated;

    # save secondary placements...
    my @place
      = MT::Placement->load( { entry_id => $obj->id, is_primary => 0 } );
    for my $place (@place) {
        $place->remove;
        $placements_updated = 1;
    }
    my @add_cat_obj;
    for my $cat_id (@add_cat) {
        my $cat = $cat_class->load($cat_id);

        # blog_id sanity check
        next if !$cat || $cat->blog_id != $obj->blog_id;

        my $place = MT::Placement->new;
        $place->entry_id( $obj->id );
        $place->blog_id( $obj->blog_id );
        $place->is_primary(0);
        $place->category_id($cat_id);
        $place->save
          or return
          $app->error(
                       $app->translate(
                               "Saving placement failed: [_1]", $place->errstr
                       )
          );
        $placements_updated = 1;
        push @add_cat_obj, $cat;
    } ## end for my $cat_id (@add_cat)
    if ($placements_updated) {
        unshift @add_cat_obj, $obj->cache_property('category')
          if $obj->cache_property('category');
        $obj->cache_property( 'categories', undef, [] );
        $obj->cache_property( 'categories', undef, \@add_cat_obj );
    }

    $app->run_callbacks( 'cms_post_save.' . $type, $app, $obj, $orig_obj );

    ## If the saved status is RELEASE, or if the *previous* status was
    ## RELEASE, then rebuild entry archives, indexes, and send the
    ## XML-RPC ping(s). Otherwise the status was and is HOLD, and we
    ## don't have to do anything.
    if ( ( $obj->status || 0 ) == MT::Entry::RELEASE()
         || $status_old eq MT::Entry::RELEASE() )
    {
        if ( $app->config('DeleteFilesAtRebuild') && $orig_obj ) {
            my $file = archive_file_for( $obj, $blog, $archive_type );
            if ( $file ne $orig_file || $obj->status != MT::Entry::RELEASE() )
            {
                $app->publisher->remove_entry_archive_file(
                                                  Entry       => $orig_obj,
                                                  ArchiveType => $archive_type
                );
            }
        }

        # If there are no static pages, just rebuild indexes.
        if ( $blog->count_static_templates($archive_type) == 0
             || MT::Util->launch_background_tasks() )
        {
            my $res = MT::Util::start_background_task(
                sub {
                    $app->run_callbacks('pre_build');
                    $app->rebuild_entry(
                                Entry             => $obj,
                                BuildDependencies => 1,
                                OldEntry          => $orig_obj,
                                OldPrevious       => ($previous_old)
                                ? $previous_old->id
                                : undef,
                                OldNext => ($next_old) ? $next_old->id : undef
                    ) or return $app->publish_error();
                    $app->run_callbacks( 'rebuild', $blog );
                    $app->run_callbacks('post_build');
                    1;
                }
            );
            return unless $res;
            return
              ping_continuation(
                                 $app, $obj, $blog,
                                 OldStatus => $status_old,
                                 IsNew     => $is_new,
              );
        } ## end if ( $blog->count_static_templates...)
        else {
            return
              $app->redirect(
                    $app->uri(
                        'mode' => 'start_rebuild',
                        args   => {
                            blog_id    => $obj->blog_id,
                            'next'     => 0,
                            type       => 'entry-' . $obj->id,
                            entry_id   => $obj->id,
                            is_new     => $is_new,
                            old_status => $status_old,
                            (
                              $previous_old
                              ? ( old_previous => $previous_old->id )
                              : ()
                            ),
                            ( $next_old ? ( old_next => $next_old->id ) : () )
                        }
                    )
              );
        } ## end else [ if ( $blog->count_static_templates...)]
    } ## end if ( ( $obj->status ||...))
    _finish_rebuild_ping( $app, $obj, !$id );
} ## end sub save

sub save_entries {
    my $app   = shift;
    my $q     = $app->query;
    my $perms = $app->permissions;
    my $type  = $q->param('_type');
    return $app->errtrans("Permission denied.")
      unless $perms
          && (
               $type eq 'page'
               ? ( $perms->can_manage_pages )
               : (    $perms->can_publish_post
                   || $perms->can_create_post
                   || $perms->can_edit_all_posts )
          );

    $app->validate_magic() or return;
    my @p = $q->param;
    require MT::Entry;
    require MT::Placement;
    require MT::Log;
    my $blog_id        = $q->param('blog_id');
    my $this_author    = $app->user;
    my $this_author_id = $this_author->id;
    for my $p (@p) {
        next unless $p =~ /^category_id_(\d+)/;
        my $id = $1;
        my $entry = MT::Entry->load($id) or next;
        return $app->error( $app->translate("Permission denied.") )
          unless $perms
              && (
                   $type eq 'page'
                   ? ( $perms->can_manage_pages )
                   : (    $perms->can_publish_post
                       || $perms->can_create_post
                       || $perms->can_edit_all_posts )
              );
        my $orig_obj = $entry->clone;
        if ( $perms->can_edit_entry( $entry, $this_author ) ) {
            my $author_id = $q->param( 'author_id_' . $id );
            $entry->author_id( $author_id ? $author_id : 0 );
            $entry->title( scalar $q->param( 'title_' . $id ) );
        }
        if ( $perms->can_edit_entry( $entry, $this_author, 1 ) )
        {    ## can he/she change status?
            $entry->status( scalar $q->param( 'status_' . $id ) );
            my $co = $q->param( 'created_on_' . $id );
            unless ( $co
                =~ m!(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?! )
            {
                return
                  $app->error(
                    $app->translate(
                        "Invalid date '[_1]'; authored on dates must be in the format YYYY-MM-DD HH:MM:SS.",
                        $co
                    )
                  );
            }
            my $s = $6 || 0;

            # Emit an error message if the date is bogus.
            return
              $app->error(
                $app->translate(
                    "Invalid date '[_1]'; authored on dates should be real dates.",
                    $co
                )
              )
              if $s > 59
                  || $s < 0
                  || $5 > 59
                  || $5 < 0
                  || $4 > 23
                  || $4 < 0
                  || $2 > 12
                  || $2 < 1
                  || $3 < 1
                  || ( MT::Util::days_in( $2, $1 ) < $3
                       && !MT::Util::leap_day( $0, $1, $2 ) );

            # FIXME: Should be assigning the publish_date field here
            my $ts = sprintf "%04d%02d%02d%02d%02d%02d", $1, $2, $3, $4, $5,
              $s;
            if ( $type eq 'page' ) {
                $entry->modified_on($ts);
            }
            else {
                $entry->authored_on($ts);
            }
        } ## end if ( $perms->can_edit_entry...)
        $app->run_callbacks( 'cms_pre_save.' . $type,
                             $app, $entry, $orig_obj )
          || return
          $app->error(
                       $app->translate(
                              "Saving [_1] failed: [_2]", $entry->class_label,
                              $app->errstr
                       )
          );
        $entry->save
          or return
          $app->error(
                       $app->translate(
                            "Saving entry '[_1]' failed: [_2]", $entry->title,
                            $entry->errstr
                       )
          );
        my $cat_id = $q->param("category_id_$id");
        my $place
          = MT::Placement->load( { entry_id => $id, is_primary => 1 } );
        if ( $place && !$cat_id ) {
            $place->remove
              or return
              $app->error(
                           $app->translate(
                                            "Removing placement failed: [_1]",
                                            $place->errstr
                           )
              );
        }
        elsif ($cat_id) {
            unless ($place) {
                $place = MT::Placement->new;
                $place->entry_id($id);
                $place->blog_id($blog_id);
                $place->is_primary(1);
            }
            $place->category_id( scalar $q->param($p) );
            $place->save
              or return
              $app->error(
                           $app->translate(
                                            "Saving placement failed: [_1]",
                                            $place->errstr
                           )
              );
        }
        my $message;
        if ( $orig_obj->status ne $entry->status ) {
            $message = $app->translate(
                "[_1] '[_2]' (ID:[_3]) edited and its status changed from [_4] to [_5] by user '[_6]'",
                $entry->class_label,
                $entry->title,
                $entry->id,
                $app->translate(
                                 MT::Entry::status_text( $orig_obj->status )
                ),
                $app->translate( MT::Entry::status_text( $entry->status ) ),
                $this_author->name
            );
        }
        else {
            $message
              = $app->translate(
                               "[_1] '[_2]' (ID:[_3]) edited by user '[_4]'",
                               $entry->class_label, $entry->title, $entry->id,
                               $this_author->name );
        }
        $app->log( {
                     message  => $message,
                     level    => MT::Log::INFO(),
                     class    => $entry->class,
                     category => 'edit',
                     metadata => $entry->id
                   }
        );
        $app->run_callbacks( 'cms_post_save.' . $type,
                             $app, $entry, $orig_obj );
    } ## end for my $p (@p)
    $app->add_return_arg( 'saved' => 1, is_power_edit => 1 );
    $app->call_return;
} ## end sub save_entries

sub rebuild_entry {
    my $app = shift;
    my $q   = $app->query;

    # TODO - always in a blog context?
    # TODO - permission check?
    my $blog       = $app->blog;
    my $return_val = { success => 0 };
    my $entries    = MT->model('entry')->lookup_multi( [ $q->param('id') ] );
  ENTRY: for my $entry (@$entries) {
        next ENTRY if !defined $entry;
        next ENTRY if $entry->blog_id != $blog->id;
        if ( $entry->status == MT::Entry::HOLD() ) {
            $entry->status( MT::Entry::RELEASE() );
            $entry->save;
        }
        $return_val->{success}
          = $app->rebuild_entry( Blog => $blog, Entry => $entry, Force => 1,
          );
        $return_val->{permalink}     = $entry->permalink;
        $return_val->{permalink_rel} = $entry->permalink;
        my $base = $entry->blog->site_url;
        $return_val->{permalink_rel} =~ s/$base//;
        unless ( $return_val->{success} ) {
            $return_val->{errstr} = $app->errstr;
        }
    }
    return _send_json_response( $app, $return_val );
} ## end sub rebuild_entry

sub get_entry {
    my $app        = shift;
    my $q          = $app->query;
    my $blog       = $app->blog;
    my $return_val = { success => 0 };
    my $e          = MT->model('entry')->load( $q->param('id') );
    my $hash       = $e->to_hash();
    foreach my $key ( keys %$hash ) {
        my $newkey = $key;
        $newkey =~ s/\./_/g;
        if ( ref $hash->{$key} eq 'CODE' ) {
            $return_val->{entry}->{$newkey} = &{ $hash->{$key} };
        }
        else {
            $return_val->{entry}->{$newkey} = $hash->{$key};
        }
    }
    return _send_json_response( $app, $return_val );
}

sub _send_json_response {
    my ( $app, $result ) = @_;
    require JSON;
    my $json = JSON::objToJson($result);
    $app->send_http_header("");
    $app->print($json);
    return $app->{no_print_body} = 1;
    return undef;
}

sub send_pings {
    my $app = shift;
    my $q   = $app->query;
    $app->validate_magic() or return;
    require MT::Entry;
    require MT::Blog;
    my $blog  = MT::Blog->load( scalar $q->param('blog_id') );
    my $entry = MT::Entry->load( scalar $q->param('entry_id') );
    ## MT::ping_and_save pings each of the necessary URLs, then processes
    ## the return value from MT::ping to update the list of URLs pinged
    ## and not successfully pinged. It returns the return value from
    ## MT::ping for further processing. If a fatal error occurs, it returns
    ## undef.
    my $results = $app->ping_and_save(
                                   Blog      => $blog,
                                   Entry     => $entry,
                                   OldStatus => scalar $q->param('old_status')
    ) or return;
    my $has_errors = 0;
    require MT::Log;
    for my $res (@$results) {
        $has_errors++,
          $app->log( {
                       message =>
                         $app->translate(
                                    "Ping '[_1]' failed: [_2]",
                                    $res->{url},
                                    encode_text( $res->{error}, undef, undef )
                         ),
                       class => 'system',
                       level => MT::Log::WARNING()
                     }
          ) unless $res->{good};
    }
    _finish_rebuild_ping( $app, $entry, scalar $q->param('is_new'),
                          $has_errors );
} ## end sub send_pings

sub pinged_urls {
    my $app   = shift;
    my $perms = $app->permissions
      or return $app->error( $app->translate("No permissions") );
    my %param;
    my $entry_id = $app->query->param('entry_id');
    require MT::Entry;
    my $entry = MT::Entry->load($entry_id)
      or return $app->error(
                   $app->translate( 'Can\'t load entry #[_1].', $entry_id ) );
    $param{url_loop} = [ map { { url => $_ } } @{ $entry->pinged_url_list } ];
    $param{failed_url_loop} = [ map { { url => $_ } }
                          @{ $entry->pinged_url_list( OnlyFailures => 1 ) } ];
    $app->load_tmpl( 'popup/pinged_urls.tmpl', \%param );
}

sub save_entry_prefs {
    my $app   = shift;
    my $perms = $app->permissions
      or return $app->error( $app->translate("No permissions") );
    $app->validate_magic() or return;
    my $q     = $app->query;
    my $prefs = $app->_entry_prefs_from_params;
    $perms->entry_prefs($prefs);
    $perms->save
      or return $app->error(
          $app->translate( "Saving permissions failed: [_1]", $perms->errstr )
      );
    $app->send_http_header("text/json");
    return "true";
}

sub publish_entries {
    my $app = shift;
    require MT::Entry;
    update_entry_status( $app, MT::Entry::RELEASE(),
                         $app->query->param('id') );
}

sub draft_entries {
    my $app = shift;
    require MT::Entry;
    update_entry_status( $app, MT::Entry::HOLD(), $app->query->param('id') );
}

sub open_batch_editor {
    my $app = shift;
    my $q   = $app->query;
    my @ids = $q->param('id');

    $q->param( 'is_power_edit', 1 );
    $q->param( 'filter',        'power_edit' );
    $q->param( 'filter_val',    \@ids );
    $q->param( 'type',          $q->param('_type') );
    $app->mode(
          'list_' . ( 'entry' eq $q->param('_type') ? 'entries' : 'pages' ) );
    $app->forward( "list_entry", { type => $q->param('_type') } );
}

sub build_entry_table {
    my $app    = shift;
    my $q      = $app->query;
    my (%args) = @_;

    my $app_author = $app->user;
    my $perms      = $app->permissions;
    my $type       = $args{type};
    my $class      = $app->model($type);

    my $list_pref = $app->list_pref($type);
    if ( $args{is_power_edit} ) {
        delete $list_pref->{view_expanded};
    }
    my $iter;
    if ( $args{load_args} ) {
        $iter = $class->load_iter( @{ $args{load_args} } );
    }
    elsif ( $args{iter} ) {
        $iter = $args{iter};
    }
    elsif ( $args{items} ) {
        $iter = sub { shift @{ $args{items} } };
    }
    return [] unless $iter;
    my $limit         = $args{limit};
    my $is_power_edit = $args{is_power_edit} || 0;
    my $param         = $args{param} || {};

    ## Load list of categories for display in filter pulldown (and selection
    ## pulldown on power edit page).
    my ( $c_data, %cats );
    my $blog_id = $q->param('blog_id');
    if ($blog_id) {
        $c_data =
          $app->_build_category_list( blog_id => $blog_id,
                                      type    => $class->container_type, );
        my $i = 0;
        for my $row (@$c_data) {
            $row->{category_index} = $i++;
            my $spacer = $row->{category_label_spacer} || '';
            $spacer =~ s/\&nbsp;/\\u00A0/g;
            $row->{category_label_js}
              = $spacer . encode_js( $row->{category_label} );
            $cats{ $row->{category_id} } = $row;
        }
        $param->{category_loop} = $c_data;
    }

    my ( $date_format, $datetime_format );

    if ($is_power_edit) {
        $date_format     = "%Y.%m.%d";
        $datetime_format = "%Y-%m-%d %H:%M:%S";
    }
    else {
        $date_format     = MT::App::CMS::LISTING_DATE_FORMAT();
        $datetime_format = MT::App::CMS::LISTING_DATETIME_FORMAT();
    }

    my @cat_list;
    if ($is_power_edit) {
        @cat_list
          = sort { $cats{$a}->{category_index} <=> $cats{$b}->{category_index} }
          keys %cats;
    }

    my @data;
    my %blogs;
    require MT::Blog;
    my $title_max_len = const('DISPLAY_LENGTH_EDIT_ENTRY_TITLE');
    my $excerpt_max_len
      = const('DISPLAY_LENGTH_EDIT_ENTRY_TEXT_FROM_EXCERPT');
    my $text_max_len = const('DISPLAY_LENGTH_EDIT_ENTRY_TEXT_BREAK_UP');
    my %blog_perms;
    $blog_perms{ $perms->blog_id } = $perms if $perms;

    while ( my $obj = $iter->() ) {
        my $blog_perms;
        if ( !$app_author->is_superuser() ) {
            $blog_perms = $blog_perms{ $obj->blog_id }
              || $app_author->blog_perm( $obj->blog_id );
        }

        my $row = $obj->get_values;
        $row->{text} ||= '';
        if ( my $ts
             = ( $type eq 'page' ) ? $obj->modified_on : $obj->authored_on )
        {
            $row->{created_on_formatted}
              = format_ts( $date_format, $ts, $obj->blog,
                        $app->user ? $app->user->preferred_language : undef );
            $row->{created_on_time_formatted}
              = format_ts( $datetime_format, $ts, $obj->blog,
                        $app->user ? $app->user->preferred_language : undef );
            $row->{created_on_relative}
              = relative_date( $ts, time, $obj->blog );
        }
        my $author = $obj->author;
        $row->{author_name}
          = $author ? $author->name : $app->translate('(user deleted)');
        if ( my $cat = $obj->category ) {
            $row->{category_label}    = $cat->label;
            $row->{category_basename} = $cat->basename;
        }
        else {
            $row->{category_label}    = '';
            $row->{category_basename} = '';
        }
        $row->{file_extension} = $obj->blog ? $obj->blog->file_extension : '';
        $row->{title_short} = $obj->title;
        if ( !defined( $row->{title_short} ) || $row->{title_short} eq '' ) {
            my $title = remove_html( $obj->text );
            $row->{title_short}
              = substr_text( defined($title) ? $title : "", 0,
                             $title_max_len )
              . '...';
        }
        else {
            $row->{title_short} = remove_html( $row->{title_short} );
            $row->{title_short}
              = substr_text( $row->{title_short}, 0, $title_max_len + 3 )
              . '...'
              if length_text( $row->{title_short} ) > $title_max_len;
        }
        if ( $row->{excerpt} ) {
            $row->{excerpt} = remove_html( $row->{excerpt} );
        }
        if ( !$row->{excerpt} ) {
            my $text = remove_html( $row->{text} ) || '';
            $row->{excerpt} = first_n_text( $text, $excerpt_max_len );
            if ( length($text) > length( $row->{excerpt} ) ) {
                $row->{excerpt} .= ' ...';
            }
        }
        $row->{text} = break_up_text( $row->{text}, $text_max_len )
          if $row->{text};
        $row->{title_long} = remove_html( $obj->title );
        $row->{status_text}
          = $app->translate( MT::Entry::status_text( $obj->status ) );
        $row->{ "status_" . MT::Entry::status_text( $obj->status ) } = 1;
        my @tags = $obj->get_tags();
        $row->{tag_loop}                 = \@tags;
        $row->{comments_enabled}         = $obj->allow_comments;
        $row->{comment_count}            = $obj->comment_count;
        $row->{entry_permalink_relative} = $obj->permalink;
        my $base = $obj->blog->site_url;
        $row->{entry_permalink_relative} =~ s/$base//;

        $row->{has_edit_access} = $app_author->is_superuser
          || (    ( 'entry' eq $type )
               && $blog_perms
               && $blog_perms->can_edit_entry( $obj, $app_author ) )
          || (    ( 'page' eq $type )
               && $blog_perms
               && $blog_perms->can_manage_pages );
        if ($is_power_edit) {
            $row->{has_publish_access} = $app_author->is_superuser
              || (    ( 'entry' eq $type )
                   && $blog_perms
                   && $blog_perms->can_edit_entry( $obj, $app_author, 1 ) )
              || (    ( 'page' eq $type )
                   && $blog_perms
                   && $blog_perms->can_manage_pages );
            $row->{is_editable} = $row->{has_edit_access};

            ## This is annoying. In order to generate and pre-select the
            ## category, user, and status pull down menus, we need to
            ## have a separate *copy* of the list of categories and
            ## users for every entry listed, so that each row in the list
            ## can "know" whether it is selected for this entry or not.
            my @this_c_data;
            my $this_category_id
              = $obj->category ? $obj->category->id : undef;
            for my $c_id (@cat_list) {
                push @this_c_data, { %{ $cats{$c_id} } };
                $this_c_data[-1]{category_is_selected}
                  = $this_category_id && $this_category_id == $c_id ? 1 : 0;
            }
            $row->{row_category_loop} = \@this_c_data;

            if ( $obj->author ) {
                $row->{row_author_name} = $obj->author->name;
                $row->{row_author_id}   = $obj->author->id;
            }
            else {
                $row->{row_author_name}
                  = $app->translate( '(user deleted - ID:[_1])',
                                     $obj->author_id );
                $row->{row_author_id} = $obj->author_id,;
            }
        } ## end if ($is_power_edit)
        if ( my $blog = $blogs{ $obj->blog_id }
             ||= MT::Blog->load( $obj->blog_id ) )
        {
            $row->{weblog_id}   = $blog->id;
            $row->{weblog_name} = $blog->name;
        }
        if ( $obj->status == MT::Entry::RELEASE() ) {
            $row->{entry_permalink} = $obj->permalink;
        }
        $row->{object} = $obj;
        push @data, $row;
    } ## end while ( my $obj = $iter->...)
    return [] unless @data;

    $param->{entry_table}[0] = {%$list_pref};
    $param->{object_loop} = $param->{entry_table}[0]{object_loop} = \@data;
    $app->load_list_actions( $type, \%$param ) unless $is_power_edit;
    \@data;
} ## end sub build_entry_table

sub quickpost_js {
    my $app     = shift;
    my ($type)  = @_;
    my $blog_id = $app->blog->id;
    my $blog    = $app->model('blog')->load($blog_id)
      or return $app->error(
                     $app->translate( 'Can\'t load blog #[_1].', $blog_id ) );
    my %args = ( '_type' => $type, blog_id => $blog_id, qp => 1 );
    my $uri = $app->base . $app->uri( 'mode' => 'view', args => \%args );
    my $script
      = qq!javascript:d=document;w=window;t='';if(d.selection)t=d.selection.createRange().text;else{if(d.getSelection)t=d.getSelection();else{if(w.getSelection)t=w.getSelection()}}void(w.open('$uri&title='+encodeURIComponent(d.title)+'&text='+encodeURIComponent(d.location.href)+encodeURIComponent('<br/><br/>')+encodeURIComponent(t),'_blank','scrollbars=yes,status=yes,resizable=yes,location=yes'))!;

    # Translate the phrase here to avoid ActivePerl DLL bug.
    $app->translate(
        '<a href="[_1]">QuickPost to [_2]</a> - Drag this link to your browser\'s toolbar then click it when you are on a site you want to blog about.',
        encode_html($script),
        encode_html( $blog->name )
    );
}

sub can_view {
    my ( $eh, $app, $id, $objp ) = @_;
    my $perms = $app->permissions;
    if ( !$id && !$perms->can_create_post ) {
        return 0;
    }
    if ($id) {
        my $obj = $objp->force();
        if ( !$perms->can_edit_entry( $obj, $app->user ) ) {
            return 0;
        }
    }
    1;
}

sub can_delete {
    my ( $eh, $app, $obj ) = @_;
    my $author = $app->user;
    return 1 if $author->is_superuser();
    my $perms = $app->permissions;
    if ( !$perms || $perms->blog_id != $obj->blog_id ) {
        $perms ||= $author->permissions( $obj->blog_id );
    }
    return $perms && $perms->can_edit_entry( $obj, $author );
}

sub pre_save {
    my $eh = shift;
    my ( $app, $obj ) = @_;
    my $q = $app->query;

    # save tags
    my $tags = $q->param('tags');
    if ( defined $tags ) {
        my $blog   = $app->blog;
        my $fields = $blog->smart_replace_fields;
        if ( $fields =~ m/tags/ig ) {
            $tags = MT::App::CMS::_convert_word_chars( $app, $tags );
        }

        require MT::Tag;
        my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
        my @tags = MT::Tag->split( $tag_delim, $tags );
        if (@tags) {
            $obj->set_tags(@tags);
        }
        else {
            $obj->remove_tags();
        }
    }

    # update text heights if necessary
    if ( my $perms = $app->permissions ) {
        my $prefs = $perms->entry_prefs || $app->load_default_entry_prefs;
        my $text_height = $q->param('text_height');
        if ( defined $text_height ) {
            my ($pref_text_height) = $prefs =~ m/\bbody:(\d+)\b/;
            $pref_text_height ||= 0;
            if ( $text_height != $pref_text_height ) {
                if ( $prefs =~ m/\bbody\b/ ) {
                    $prefs =~ s/\bbody(:\d+)\b/body:$text_height/;
                }
                else {
                    $prefs = 'body:' . $text_height . ',' . $prefs;
                }
            }
        }
        if ( $prefs ne ( $perms->entry_prefs || '' ) ) {
            $perms->entry_prefs($prefs);
            $perms->save;
        }
    } ## end if ( my $perms = $app->permissions)
    $obj->discover_tb_from_entry();
    1;
} ## end sub pre_save

sub post_save {
    my $eh = shift;
    my ( $app, $obj ) = @_;
    my $sess_obj = $app->autosave_session_obj;
    $sess_obj->remove if $sess_obj;
    1;
}

sub post_delete {
    my ( $eh, $app, $obj ) = @_;

    my $sess_obj = $app->autosave_session_obj;
    $sess_obj->remove if $sess_obj;

    $app->log( {
                 message =>
                   $app->translate(
                                   "Entry '[_1]' (ID:[_2]) deleted by '[_3]'",
                                   $obj->title, $obj->id, $app->user->name
                   ),
                 level    => MT::Log::INFO(),
                 class    => 'system',
                 category => 'delete'
               }
    );
}

sub update_entry_status {
    my $app = shift;
    my ( $new_status, @ids ) = @_;
    return $app->errtrans("Need a status to update entries")
      unless $new_status;
    return $app->errtrans("Need entries to update status") unless @ids;
    my @bad_ids;
    my %rebuild_these;
    require MT::Entry;

    my $app_author = $app->user;
    my $perms      = $app->permissions;

    foreach my $id (@ids) {
        my $entry = MT::Entry->load($id)
          or return
          $app->errtrans( "One of the entries ([_1]) did not actually exist",
                          $id );

        return $app->error( $app->translate('Permission denied.') )
          unless $app_author->is_superuser
              || (    ( $entry->class eq 'entry' )
                   && $perms
                   && $perms->can_edit_entry( $entry, $app_author, 1 ) )
              || (    ( $entry->class eq 'page' )
                   && $perms
                   && $perms->can_manage_pages );

        if ( $app->config('DeleteFilesAtRebuild')
             && ( MT::Entry::RELEASE() eq $entry->status ) )
        {
            my $archive_type
              = $entry->class eq 'page' ? 'Page' : 'Individual';
            $app->publisher->remove_entry_archive_file(
                                                  Entry       => $entry,
                                                  ArchiveType => $archive_type
            );
        }
        my $old_status = $entry->status;
        $entry->status($new_status);
        $entry->save() and $rebuild_these{$id} = 1;
        my $message = $app->translate(
                     "[_1] '[_2]' (ID:[_3]) status changed from [_4] to [_5]",
                     $entry->class_label,
                     $entry->title,
                     $entry->id,
                     $app->translate( MT::Entry::status_text($old_status) ),
                     $app->translate( MT::Entry::status_text($new_status) )
        );
        $app->log( {
                     message  => $message,
                     level    => MT::Log::INFO(),
                     class    => $entry->class,
                     category => 'edit',
                     metadata => $entry->id
                   }
        );
    } ## end foreach my $id (@ids)
    $app->rebuild_these( \%rebuild_these, how => MT::App::CMS::NEW_PHASE() );
} ## end sub update_entry_status

sub _finish_rebuild_ping {
    my $app = shift;
    my ( $entry, $is_new, $ping_errors ) = @_;
    $app->redirect(
          $app->uri(
              'mode' => 'view',
              args   => {
                  '_type' => $entry->class,
                  blog_id => $entry->blog_id,
                  id      => $entry->id,
                  ( $is_new ? ( saved_added => 1 ) : ( saved_changes => 1 ) ),
                  ( $ping_errors ? ( ping_errors => 1 ) : () )
              }
          )
    );
}

sub ping_continuation {
    my $app = shift;
    my ( $entry, $blog, %options ) = @_;
    my $list = $app->needs_ping(
                                 Entry     => $entry,
                                 Blog      => $blog,
                                 OldStatus => $options{OldStatus}
    );
    require MT::Entry;
    if ( $entry->status == MT::Entry::RELEASE() && $list ) {
        my @urls = map { { url => $_ } } @$list;
        $app->load_tmpl(
                         'pinging.tmpl',
                         {
                            blog_id    => $blog->id,
                            entry_id   => $entry->id,
                            old_status => $options{OldStatus},
                            is_new     => $options{IsNew},
                            url_list   => \@urls,
                         }
        );
    }
    else {
        _finish_rebuild_ping( $app, $entry, $options{IsNew} );
    }
} ## end sub ping_continuation

sub delete {
    my $app = shift;
    $app->validate_magic() or return;
    require MT::Blog;
    my $q       = $app->query;
    my $blog_id = $q->param('blog_id');
    my $blog    = MT::Blog->load($blog_id)
      or return $app->error(
                     $app->translate( 'Can\'t load blog #[_1].', $blog_id ) );

    my $can_background = ( $blog->count_static_templates('Individual') == 0
                           || MT::Util->launch_background_tasks() ) ? 1 : 0;

    my %rebuild_recip;
    for my $id ( $q->param('id') ) {
        my $class = $app->model("entry");
        my $obj   = $class->load($id);
        return $app->call_return unless $obj;

        $app->run_callbacks( 'cms_delete_permission_filter.entry',
                             $app, $obj )
          || return $app->error(
               $app->translate( "Permission denied: [_1]", $app->errstr() ) );

        my %recip =
          $app->publisher->rebuild_deleted_entry( Entry => $obj,
                                                  Blog  => $blog );

        # Remove object from database
        $obj->remove()
          or return
          $app->errtrans( 'Removing [_1] failed: [_2]',
                          $app->translate('entry'),
                          $obj->errstr );
        $app->run_callbacks( 'cms_post_delete.entry', $app, $obj );
    } ## end for my $id ( $q->param(...))

    $app->add_return_arg( saved_deleted => 1 );
    if ( $q->param('is_power_edit') ) {
        $app->add_return_arg( is_power_edit => 1 );
    }

    if ( $app->config('RebuildAtDelete') ) {
        if ($can_background) {
            my $res = MT::Util::start_background_task(
                sub {
                    my $res =
                      $app->rebuild_archives(
                                              Blog  => $blog,
                                              Recip => \%rebuild_recip,
                      ) or return $app->publish_error();
                    $app->rebuild_indexes( Blog => $blog )
                      or return $app->publish_error();
                    $app->run_callbacks( 'rebuild', $blog );
                    1;
                }
            );
        }
        else {
            $app->rebuild_archives(
                                    Blog  => $blog,
                                    Recip => \%rebuild_recip,
            ) or return $app->publish_error();
            $app->rebuild_indexes( Blog => $blog )
              or return $app->publish_error();

            $app->run_callbacks( 'rebuild', $blog );
        }

        $app->add_return_arg( no_rebuild => 1 );
        my %params = (
                       is_full_screen  => 1,
                       redirect_target => $app->app_path
                         . $app->script . '?'
                         . $app->return_args,
        );
        return $app->load_tmpl( 'rebuilding.tmpl', \%params );
    } ## end if ( $app->config('RebuildAtDelete'...))

    return $app->call_return();
} ## end sub delete

1;
__END__

=head1 NAME

MT::CMS::Entry

=head1 METHODS

=head2 build_entry_table

=head2 build_junk_table

=head2 can_delete

=head2 can_view

=head2 delete

=head2 draft_entries

=head2 edit

=head2 list

=head2 open_batch_editor

=head2 ping_continuation

=head2 pinged_urls

=head2 post_delete

=head2 post_save

=head2 pre_save

=head2 preview

=head2 publish_entries

=head2 quickpost_js

=head2 save

=head2 save_entries

=head2 save_entry_prefs

=head2 send_pings

=head2 update_entry_status

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
