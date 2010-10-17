package TrackBacks::Callbacks;

use strict;

sub edit {
    my $cb = shift;
    my ($app, $id, $obj, $param) = @_;
    my $q = $app->query;
    my $perms = $app->permissions;
    my $blog = $app->blog;
    my $blog_id = $q->param('blog_id');
    my $type = $q->param('_type');

    if ($id) {
        $param->{nav_trackbacks} = 1;
        $app->add_breadcrumb(
            $app->translate('TrackBacks'),
            $app->uri(
                'mode' => 'list_pings',
                args   => { blog_id => $blog_id }
            )
        );
        $app->add_breadcrumb( $app->translate('Edit TrackBack') );
        $param->{approved}           = $q->param('approved');
        $param->{unapproved}         = $q->param('unapproved');
        $param->{has_publish_access} = 1 if $app->user->is_superuser;
        $param->{has_publish_access} = (
            ( $perms->can_manage_feedback || $perms->can_edit_all_posts )
            ? 1
            : 0
        ) unless $app->user->is_superuser;
        require MT::Trackback;

        if ( my $tb = MT::Trackback->load( $obj->tb_id ) ) {
            if ( $tb->entry_id ) {
                $param->{entry_ping} = 1;
                require MT::Entry;
                if ( my $entry = MT::Entry->load( $tb->entry_id ) ) {
                    $param->{entry_title} = $entry->title;
                    $param->{entry_id}    = $entry->id;
                    unless ( $param->{has_publish_access} ) {
                        $param->{has_publish_access} =
                          ( $perms->can_publish_post
                              && ( $app->user->id == $entry->author_id ) )
                          ? 1
                          : 0;
                    }
                }
            }
            elsif ( $tb->category_id ) {
                $param->{category_ping} = 1;
                require MT::Category;
                if ( my $cat = MT::Category->load( $tb->category_id ) ) {
                    $param->{category_id}    = $cat->id;
                    $param->{category_label} = $cat->label;
                }
            }
        }

        $param->{"ping_approved"} = $obj->is_published
          or $param->{"ping_pending"} = $obj->is_moderated
          or $param->{"is_junk"}      = $obj->is_junk;

        ## Load next and previous entries for next/previous links
        if ( my $next = $obj->next ) {
            $param->{next_ping_id} = $next->id;
        }
        if ( my $prev = $obj->previous ) {
            $param->{previous_ping_id} = $prev->id;
        }
        my $parent = $obj->parent;
        if ( $parent && ( $parent->isa('MT::Entry') ) ) {
            if ( $parent->status == MT::Entry::RELEASE() ) {
                $param->{entry_permalink} = $parent->permalink;
            }
        }

        if ( $obj->junk_log ) {
            require MT::CMS::Comment;
            MT::CMS::Comment::build_junk_table( $app, param => $param, object => $obj );
        }

        $param->{created_on_time_formatted} =
          format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $obj->created_on(), $blog, $app->user ? $app->user->preferred_language : undef );
        $param->{created_on_day_formatted} =
          format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $obj->created_on(), $blog, $app->user ? $app->user->preferred_language : undef );

        $param->{search_label} = $app->translate('TrackBacks');
        $param->{object_type}  = 'ping';

        $app->load_list_actions( $type, $param );

        # since MT::App::build_page clobbers it:
        $param->{source_blog_name} = $param->{blog_name};
    }
    1;
}

sub can_view {
    my $eh = shift;
    my ( $app, $id, $objp ) = @_;
    my $obj = $objp->force() or return 0;
    require MT::Trackback;
    my $tb    = MT::Trackback->load( $obj->tb_id );
    my $perms = $app->permissions;
    if ($tb) {
        if ( $tb->entry_id ) {
            require MT::Entry;
            my $entry = MT::Entry->load( $tb->entry_id );
            return ( !$entry
                  || $entry->author_id == $app->user->id
                  || $perms->can_manage_feedback
                  || $perms->can_edit_all_posts );
        }
        elsif ( $tb->category_id ) {
            require MT::Category;
            my $cat = MT::Category->load( $tb->category_id );
            return $cat && $perms->can_edit_categories;
        }
    }
    else {
        return 0;    # no TrackBack center--no edit
    }
}

sub can_save {
    my ( $eh, $app, $id ) = @_;
	my $q = $app->param;    
    return 0 unless $id;    # Can't create new pings here
    return 1 if $app->user->is_superuser();
    my $perms = $app->permissions;
    return 1
      if $perms
      && ( $perms->can_edit_all_posts
        || $perms->can_manage_feedback );
    my $p      = MT::TBPing->load($id)
        or return 0;
    my $tbitem = $p->parent;
    if ( $tbitem->isa('MT::Entry') ) {
        if ( $perms && $perms->can_publish_post && $perms->can_create_post ) {
            return $tbitem->author_id == $app->user->id;
        }
        elsif ( $perms->can_create_post ) {
            return ( $tbitem->author_id == $app->user->id )
              && (
                ( $p->is_junk && ( 'junk' eq $q->param('status') ) )
                || ( $p->is_moderated
                    && ( 'moderate' eq $q->param('status') ) )
                || ( $p->is_published
                    && ( 'publish' eq $q->param('status') ) )
              );
        }
        elsif ( $perms && $perms->can_publish_post ) {
            return 0 unless $tbitem->author_id == $app->user->id;
            return 0
              unless ( $p->excerpt eq $q->param('excerpt') )
              && ( $p->blog_name  eq $q->param('blog_name') )
              && ( $p->title      eq $q->param('title') )
              && ( $p->source_url eq $q->param('source_url') );
        }
    }
    else {
        return $perms && $perms->can_edit_categories;
    }
}

sub can_delete {
    my ( $eh, $app, $obj ) = @_;
    my $author = $app->user;
    return 1 if $author->is_superuser();
    my $perms = $app->permissions;
    require MT::Trackback;
    my $tb = MT::Trackback->load( $obj->tb_id )
        or return 0;
    if ( my $entry = $tb->entry ) {
        if ( !$perms || $perms->blog_id != $entry->blog_id ) {
            $perms ||= $author->permissions( $entry->blog_id );
        }

        # publish_post allows entry author to delete comment.
        return 1
          if $perms->can_edit_all_posts
          || $perms->can_manage_feedback
          || $perms->can_edit_entry( $entry, $author, 1 );
        return 0
          if $obj->visible;    # otherwise, visible comment can't be deleted.
        return $perms->can_edit_entry( $entry, $author );
    }
    elsif ( $tb->category_id ) {
        $perms ||= $author->permissions( $tb->blog_id );
        return ( $perms && $perms->can_edit_categories() );
    }
    return 0;
}

sub pre_save {
    my $eh = shift;
    my ( $app, $obj, $original ) = @_;
    my $q = $app->query;
    my $perms = $app->permissions;
    return 1
      unless $perms->can_publish_post
      || $perms->can_edit_categories
      || $perms->can_edit_all_posts
      || $perms->can_manage_feedback;

    unless ( $perms->can_edit_all_posts || $perms->can_manage_feedback ) {
        return 1 unless $perms->can_publish_post || $perms->can_edit_categories;
        require MT::Trackback;
        my $tb = MT::Trackback->load( $obj->tb_id )
            or return 0;
        if ($tb) {
            if ( $tb->entry_id ) {
                require MT::Entry;
                my $entry = MT::Entry->load( $tb->entry_id );
                return 1
                  if ( !$entry || $entry->author_id != $app->user->id )
                  && $perms->can_publish_post;
            }
        }
        elsif ( $tb->category_id ) {
            require MT::Category;
            my $cat = MT::Category->load( $tb->category_id );
            return 1 unless $cat && $perms->can_edit_categories;
        }
    }

    my $status = $q->param('status');
    if ( $status eq 'publish' ) {
        $obj->approve;
        if ( $original->junk_status != $obj->junk_status ) {
            $app->run_callbacks( 'handle_ham', $app, $obj );
        }
    }
    elsif ( $status eq 'moderate' ) {
        $obj->moderate;
    }
    elsif ( $status eq 'junk' ) {
        $obj->junk;
        if ( $original->junk_status != $obj->junk_status ) {
            $app->run_callbacks( 'handle_spam', $app, $obj );
        }
    }
    return 1;
}

sub post_save {
    my $eh = shift;
    my ( $app, $obj, $original ) = @_;
    require MT::Trackback;
    require MT::Entry;
    require MT::Category;
    if ( my $tb = MT::Trackback->load( $obj->tb_id ) ) {
        my ( $entry, $cat );
        if ( $tb->entry_id && ( $entry = MT::Entry->load( $tb->entry_id ) ) ) {
            if ( $obj->visible
                || ( ( $obj->visible || 0 ) != ( $original->visible || 0 ) ) )
            {
                $app->rebuild_entry( Entry => $entry, BuildIndexes => 1 )
                    or return $app->publish_error();
            }
        }
        elsif ( $tb->category_id
            && ( $cat = MT::Category->load( $tb->category_id ) ) )
        {

            # FIXME: rebuild single category
        }
    }
    1;
}

sub post_delete {
    my ( $eh, $app, $obj ) = @_;

    my ( $message, $title );
    my $obj_parent = $obj->parent();
    if ( $obj_parent->isa('MT::Category') ) {
        $title = $obj_parent->label || $app->translate('(Unlabeled category)');
        $message =
          $app->translate(
            "Ping (ID:[_1]) from '[_2]' deleted by '[_3]' from category '[_4]'",
            $obj->id, $obj->blog_name, $app->user->name, $title );
    }
    else {
        $title = $obj_parent->title || $app->translate('(Untitled entry)');
        $message =
          $app->translate(
            "Ping (ID:[_1]) from '[_2]' deleted by '[_3]' from entry '[_4]'",
            $obj->id, $obj->blog_name, $app->user->name, $title );
    }

    $app->log(
        {
            message  => $message,
            level    => MT::Log::INFO(),
            class    => 'system',
            category => 'delete'
        }
    );
}

sub post_clone_blog {
    my ($cb, $params) = @_;

    my $callback = $params->{Callback} || sub {};
    my $classes = $params->{Classes};

    my $old_blog_id = $params->{OldBlogId};
    my $new_blog_id = $params->{NewBlogId};
    my (%tb_map, $counter, $iter);

    my $entry_map = $param->{EntryMap};
    my $cat_map = $param->{CategoryMap};

    if ((!exists $classes->{'MT::Trackback'}) || $classes->{'MT::Trackback'}) {
        my $state = MT->translate("Cloning TrackBacks for blog...");
        $callback->($state, "tbs");
        require MT::Trackback;
        $iter = MT::Trackback->load_iter({ blog_id => $old_blog_id });
        $counter = 0;
        while (my $tb = $iter->()) {
            next unless ($tb->entry_id && $entry_map{$tb->entry_id}) ||
                ($tb->category_id && $cat_map{$tb->category_id});

            $callback->($state . " " . MT->translate("[_1] records processed...", $counter), 'tbs')
                if $counter && ($counter % 100 == 0);
            $counter++;
            my $tb_id = $tb->id;
            my $new_tb = $tb->clone();
            delete $new_tb->{column_values}->{id};
            delete $new_tb->{changed_cols}->{id};

            if ($tb->category_id) {
                if (my $cid = $cat_map{$tb->category_id}) {
                    my $cat_tb = MT::Trackback->load(
                        { category_id => $cid }
                    );
                    if ($cat_tb) {
                        my $changed;
                        if ($tb->passphrase) {
                            $cat_tb->passphrase($tb->passphrase);
                            $changed = 1;
                        }
                        if ($tb->is_disabled) {
                            $cat_tb->is_disabled(1);
                            $changed = 1;
                        }
                        $cat_tb->save if $changed;
                        $tb_map{$tb_id} = $cat_tb->id;
                        next;
                    }
                }
            }
            elsif ($tb->entry_id) {
                if (my $eid = $entry_map{$tb->entry_id}) {
                    my $entry_tb = MT::Entry->load($eid)->trackback;
                    if ($entry_tb) {
                        my $changed;
                        if ($tb->passphrase) {
                            $entry_tb->passphrase($tb->passphrase);
                            $changed = 1;
                        }
                        if ($tb->is_disabled) {
                            $entry_tb->is_disabled(1);
                            $changed = 1;
                        }
                        $entry_tb->save if $changed;
                        $tb_map{$tb_id} = $entry_tb->id;
                        next;
                    }
                }
            }

            # A trackback wasn't created when saving the entry/category,
            # (perhaps trackbacks are now disabled for the entry/category?)
            # so create one now
            $new_tb->entry_id($entry_map{$tb->entry_id})
                if $tb->entry_id && $entry_map{$tb->entry_id};
            $new_tb->category_id($cat_map{$tb->category_id})
                if $tb->category_id && $cat_map{$tb->category_id};
            $new_tb->blog_id($new_blog_id);
            $new_tb->save or die $new_tb->errstr;
            $tb_map{$tb_id} = $new_tb->id;
        }
        $callback->($state . " " . MT->translate("[_1] records processed.", $counter), 'tbs');

        if ((!exists $classes->{'MT::TBPing'}) || $classes->{'MT::TBPing'}) {
            my $state = MT->translate("Cloning TrackBack pings for blog...");
            $callback->($state, "pings");
            require MT::TBPing;
            $iter = MT::TBPing->load_iter({ blog_id => $old_blog_id });
            $counter = 0;
            while (my $ping = $iter->()) {
                next unless $tb_map{$ping->tb_id};
                $callback->($state . " " . MT->translate("[_1] records processed...", $counter), 'pings')
                    if $counter && ($counter % 100 == 0);
                $counter++;
                my $new_ping = $ping->clone();
                delete $new_ping->{column_values}->{id};
                delete $new_ping->{changed_cols}->{id};
                $new_ping->tb_id($tb_map{$ping->tb_id});
                $new_ping->blog_id($new_blog_id);
                $new_ping->save or die $new_ping->errstr;
            }
            $callback->($state . " " . MT->translate("[_1] records processed.", $counter), 'pings');
        }
    }
}

sub post_save_category {
    my $cb = shift;
    my ( $cat, $original ) = @_;
    ## If pings are allowed on this entry, create or update
    ## the corresponding Trackback object for this entry.
    require MT::Trackback;
    if ($cat->allow_pings) {
        my $tb;
        unless ($tb = MT::Trackback->load({
                                 category_id => $cat->id })) {
            $tb = MT::Trackback->new;
            $tb->blog_id($cat->blog_id);
            $tb->category_id($cat->id);
            $tb->entry_id(0);   ## entry_id can't be NULL
        }
        if (defined(my $pass = $cat->{__tb_passphrase})) {
            $tb->passphrase($pass);
        }
        $tb->title($cat->label);
        $tb->description($cat->description);
        my $blog = MT::Blog->load($cat->blog_id)
            or return;
        my $url = $blog->archive_url;
        $url .= '/' unless $url =~ m!/$!;
        $url .= MT::Util::archive_file_for(undef, $blog,
            'Category', $cat);
        $tb->url($url);
        $tb->is_disabled(0);
        $tb->save
            or return $cat->error($tb->errstr);
    } else {
        ## If there is a TrackBack item for this category, but
        ## pings are now disabled, make sure that we mark the
        ## object as disabled.
        if (my $tb = MT::Trackback->load({
                                  category_id => $cat->id })) {
            $tb->is_disabled(1);
            $tb->save
                or return $cat->error($tb->errstr);
        }
    }
}

sub feed_ping {
    my ( $cb, $app, $view, $feed ) = @_;
	my $q 	 = $app->query;
    my $user = $app->user;

    require MT::Blog;
    my $blog;

    # verify user has permission to view entries for given weblog
    my $blog_id = $q->param('blog_id');
    if ($blog_id) {
        if ( !$user->is_superuser ) {
            require MT::Permission;
            my $perm = MT::Permission->load(
                {   author_id => $user->id,
                    blog_id   => $blog_id
                }
            );
            return $cb->error( $app->translate("No permissions.") )
                unless $perm;
        }
        $blog = MT::Blog->load($blog_id) or return;
    }
    else {
        if ( !$user->is_superuser ) {

       # limit activity log view to only weblogs this user has permissions for
            require MT::Permission;
            my @perms = MT::Permission->load( { author_id => $user->id } );
            return $cb->error( $app->translate("No permissions.") )
                unless @perms;
            my @blog_list;
            push @blog_list, $_->blog_id foreach @perms;
            $blog_id = join ',', @blog_list;
        }
    }

    my $link = $app->base
        . $app->mt_uri(
        mode => 'list_pings',
        args => { $blog ? ( blog_id => $blog_id ) : () }
        );
    my $param = {
        feed_link  => $link,
        feed_title => $blog
        ? $app->translate( '[_1] Weblog TrackBacks', $blog->name )
        : $app->translate("All Weblog TrackBacks")
    };

    # user has permissions to view this type of feed... continue
    my $terms = $app->apply_log_filter(
        {   filter     => 'class',
            filter_val => 'ping',
            $blog_id ? ( blog_id => $blog_id ) : (),
        }
    );
    $$feed = $app->process_log_feed( $terms, $param );
}

sub edit_category_param {
    my ( $cb, $app, $param, $tmpl ) = @_;

    my $blog = $app->blog;
    if ($param->{id}) {
        my $obj = MT->model('category')->load( $param->{id} );
        require MT::Trackback;
        my $tb = MT::Trackback->load( { category_id => $obj->id } );

        if ($tb) {
            my $list_pref = $app->list_pref('ping');
            %$param = ( %$param, %$list_pref );
            my $path = $app->config('CGIPath');
            $path .= '/' unless $path =~ m!/$!;
            if ($path =~ m!^/!) {
                my ($blog_domain) = $blog->archive_url =~ m|(.+://[^/]+)|;
                $path = $blog_domain . $path;
            }

            my $script = $app->config('TrackbackScript');
            $param->{tb}     = 1;
            $param->{tb_url} = $path . $script . '/' . $tb->id;
            if ( $param->{tb_passphrase} = $tb->passphrase ) {
                $param->{tb_url} .= '/' . encode_url( $param->{tb_passphrase} );
            }
            $app->load_list_actions( 'ping', $param->{ping_table}[0],
                'pings' );
        }
    }
}

sub edit_category_source {
    my ( $cb, $app, $tmpl ) = @_;
    my $slug;
    $slug = <<END_TMPL;
    <fieldset>
        <h3><__trans phrase="Inbound TrackBacks"></h3>
<mtapp:setting
    id="allow_pings"
    label="<__trans phrase="Accept Trackbacks">"
    hint="<__trans phrase="If enabled, TrackBacks will be accepted for this category from any source.">"
    help_page="categories"
    help_section="accept_category_pings">
    <input type="checkbox" name="allow_pings" id="allow_pings" value="1" onclick="toggleSubPrefs(this); return true"<mt:if name="allow_pings"> checked="checked"</mt:if> class="cb" /> 
</mtapp:setting>

<mt:if name="tb">
    <mtapp:setting
        id="view_trackbacks"
        label="<__trans phrase="TrackBacks">">
        <div id="view_trackbacks"><strong><a href="<mt:var name="script_url">?__mode=list_pings&amp;filter=category_id&amp;filter_val=<mt:var name="id" escape="url">&amp;blog_id=<mt:var name="blog_id" escape="url">"><__trans phrase="View TrackBacks"></a></strong></div>
    </mtapp:setting>
</mt:if>
        <div id="allow_pings_prefs" style="display:<mt:if name="allow_pings">block<mt:else>none</mt:if>">
<mt:if name="tb_url">
    <mtapp:setting
        id="trackback_url"
        label="<__trans phrase="TrackBack URL for this category">"
        hint="<__trans phrase="_USAGE_CATEGORY_PING_URL">">
        <div class="textarea-wrapper">
            <input type="text" name="trackback_url" id="trackback_url" readonly="readonly" value="<mt:var name="tb_url" escape="html">" class="full-width" />
        </div>
    </mtapp:setting>
    <mtapp:setting
        id="tb_passphrase"
        label="<__trans phrase="Passphrase Protection">"
        hint="<__trans phrase="Optional">"
        help_page="categories"
        help_section="trackback_passphrase_protection">
        <div class="textarea-wrapper">
            <input name="tb_passphrase" id="tb_passphrase" class="full-width" value="<mt:var name="tb_passphrase" escape="html">" size="30" />
        </div>
    </mtapp:setting>
</mt:if>
        </div>
    </fieldset>

    <fieldset>
        <h3><__trans phrase="Outbound TrackBacks"></h3>
<mtapp:setting
    id="ping_urls"
    label="<__trans phrase="Trackback URLs">"
    hint="<__trans phrase="Enter the URL(s) of the websites that you would like to send a TrackBack to each time you create an entry in this category. (Separate URLs with a carriage return.)">"
    help_page="categories"
    help_section="categories_urls_to_ping">
    <textarea name="ping_urls" id="ping_urls" cols="" rows="" class="full-width short"><mt:var name="ping_urls" escape="html"></textarea>
</mtapp:setting>
    </fieldset>
END_TMPL
    $$tmpl =~ s{(<mt:setvarblock name="action_buttons">)}{$slug $1}msi;
}

1;
__END__
=pod

=head1 NAME

Melody TrackBack and Ping Callbacks

=head1 DESCRIPTION

The callback system in Melody is easy to use and is invoked at key areas
throughout the application. This document is a reference of the callbacks
made available through the TrackBacks addon.

=head1 OVERVIEW

What follows is a listing of each available callback, grouped by
system component. The callback is immediately followed by a I<signature>
which describes how to write your callback subroutine to accept the
parameters the callback provides.

For example, if the signature reads like this:

    callback($cb, $param1, $param2)

Then your callback subroutine should be declared as:

    sub my_callback {
        my ($cb, $param1, $param2) = @_;

    }

If the callback signature looks like this:

    callback($cb, %info)

Then your callback subroutine should be:

    sub my_callback {
        my ($cb, %info) = @_;

    }

=head1 Application Callbacks

=head2 MT::App::Trackback

This application handles receiving all TrackBack pings sent to the
Movable Type installation.

=over 4

=item * TBPingThrottleFilter

    callback($cb, $app, $trackback)

This callback is issued early on upon receiving a TrackBack ping and it
allows the callback code to return a boolean as to whether the request
should be accepted or rejected. So if the callback returns 0, it signals
a reject for the ping. Returning 1 will accept it for further processing.

    sub trackback_throttle_filter {
        my ($cb, $app, $trackback) = @_;
        ...
        $boolean; # 1 to accept, 0 to reject
    }

=item * TBPingFilter

    callback($cb, $app, $ping)

Called once the TrackBack ping object has been constructed, but before
saving it. If any TBPingFilter callback returns false, the ping will
not be saved. The callback has the following signature:

    sub trackback_filter {
        my ($cb, $app, $ping) = @_;
        ...
        $boolean; # 1 to accept, 0 to reject
    }

=back

=cut
