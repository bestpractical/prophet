package Prophet::Web::Menu;

use Moose;
use URI;

has cgi => (isa =>'CGI', is=>'ro');
has label => ( isa => 'Str', is => 'rw');
has parent => ( isa => 'Maybe[Prophet::Web::Menu]', is => 'rw', weakref => 1);
has sort_order => ( isa => 'Str', is => 'rw');
has render_children_inline => ( isa => 'Bool', is => 'rw', default => 0);
has url => ( isa => 'Str', is => 'rw');
has target => ( isa => 'Str', is => 'rw');
has class => ( isa => 'Str', is => 'rw');
has escape_label => ( isa => 'Bool', is => 'rw');

=head1 NAME

Prophet:Web::Menu - Handle the API for menu navigation

=head1 METHODS

=head2 new PARAMHASH

Creates a new L<Prophet::Web::Menu> object.  Possible keys in the
I<PARAMHASH> are C<label>, C<parent>, C<sort_order>, C<url>, and
C<active>.  See the subroutines with the respective name below for
each option's use.

=cut

sub new {
    my $package = shift;
    my $args = ref($_[0]) eq 'HASH' ? shift @_ : {@_};

    my $parent = delete $args->{'parent'};

    # Class::Accessor only wants a hashref;
    my $self = $package->SUPER::new( $args);

    # make sure our reference is weak
    $self->parent($parent) if defined $parent;

    return $self;
}


=head2 label [STRING]

Sets or returns the string that the menu item will be displayed as.

=cut

=head2 parent [MENU]

Gets or sets the parent L<Prophet::Web::Menu> of this item; this defaults
to null. This ensures that the reference is weakened.

=cut



=head2 sort_order [NUMBER]

Gets or sets the sort order of the item, as it will be displayed under
the parent.  This defaults to adding onto the end.

=head2 link

Gets or set a Jifty::Web::Link object that represents this menu item. If
you're looking to do complex ajaxy things with menus, this is likely
the option you want.

=head2 target [STRING]

Get or set the frame or pseudo-target for this link. something like L<_blank>

=cut

=head2 class [STRING]

Gets or sets the CSS class the link should have in addition to the default
classes.  This is only used if C<link> isn't specified.

=head2 url

Gets or sets the URL that the menu's link goes to.  If the link
provided is not absolute (does not start with a "/"), then is is
treated as relative to it's parent's url, and made absolute.

=cut

sub url {
    my $self = shift;
    $self->{url} = shift if @_;

    $self->{url} = URI->new_abs($self->{url}, $self->parent->url . "/")->as_string
      if defined $self->{url} and $self->parent and $self->parent->url;

    $self->{url} =~ s!///!/! if $self->{url};

    return $self->{url};
}

=head2 active [BOOLEAN]

Gets or sets if the menu item is marked as active.  Setting this
cascades to all of the parents of the menu item.

=cut

sub active {
    my $self = shift;
    if (@_) {
        $self->{active} = shift;
        $self->parent->active($self->{active}) if defined $self->parent;
    }
    return $self->{active};
}

=head2 child KEY [, PARAMHASH]

If only a I<KEY> is provided, returns the child with that I<KEY>.

Otherwise, creates or overwrites the child with that key, passing the
I<PARAMHASH> to L<Jifty::Web::Menu/new>.  Additionally, the paramhash's
C<label> defaults to the I<KEY>, and the C<sort_order> defaults to the
pre-existing child's sort order (if a C<KEY> is being over-written) or
the end of the list, if it is a new C<KEY>.

=cut

sub child {
    my $self = shift;
    my $key = shift;
    my $proto = ref $self || $self;

    if (@_) {
        $self->{children}{$key} = $proto->new({parent => $self,
                                                cgi => $self->cgi,
                                               sort_order => ($self->{children}{$key}{sort_order}
                                                          || scalar values %{$self->{children}}),
                                               label => $key,
                                               escape_label => 1,
                                               @_
                                             });
        
        # Figure out the URL
        my $child = $self->{children}{$key};
        my $url   =   $child->url;

        # Activate it
        if ( defined $url and length $url and $self->cgi->path_info ) {
            # XXX TODO cleanup for mod_perl
            my $base_path = $self->cgi->path_info;
            chomp($base_path);
            
            $base_path =~ s/index\.html$//;
            $base_path =~ s/\/+$//;
            $url =~ s/\/+$//;
            
            if ($url eq $base_path) {
                $self->{children}{$key}->active(1); 
            }
        }
    }

    return $self->{children}{$key}
}

=head2 active_child

Returns the first active child node, or C<undef> is there is none.

=cut

sub active_child {
    my $self = shift;
    foreach my $kid ($self->children) {
        return $kid if $kid->active;
    }
    return undef;
}


=head2 delete KEY

Removes the child with the provided I<KEY>.

=cut

sub delete {
    my $self = shift;
    my $key = shift;
    delete $self->{children}{$key};
}

=head2 children

Returns the children of this menu item in sorted order; as an array in
array context, or as an array reference in scalar context.

=cut

sub children {
    my $self = shift;
    my @kids = values %{$self->{children} || {}};
    @kids = sort {$a->sort_order <=> $b->sort_order} @kids;
    return wantarray ? @kids : \@kids;
}

=head2 render_as_yui_menubar [PARAMHASH]

Render menubar with YUI menu, suitable for an application's menu.
It can support arbitary levels of submenu.

=cut

sub render_as_yui_menubar {
    my $self = shift;
    my $id   = scalar $self; # XXX HACK
    
    my $buffer = ''; 
    $buffer .= $self->_render_as_yui_menu_item( class => "yuimenubar", id => $id );
    $buffer .= (qq|<script type="text/javascript">\n|
        . qq|YAHOO.util.Event.onContentReady("|.$id.qq|", function() {\n|
        . qq|var menu = new YAHOO.widget.MenuBar("|.$id.qq|", { autosubmenudisplay:true, hidedelay:750, lazyload:true, showdelay:0 });\n|
        . qq|menu.render();\n|
        . qq|});</script>|
        );
    return $buffer;
}

sub _render_as_yui_menu_item {
    my $self = shift;
    my %args = ( class => 'yuimenu', first => 0, id => undef, @_ );
    my @kids = $self->children or return;
   
    my $buffer;

    # Add the appropriate YUI class to each kid
    for my $kid ( @kids ) {
        # Skip it if it's a group heading
        next if $kid->render_children_inline and $kid->children;

        # Figure out the correct object to be setting the class on
        my $object =  $kid;

        my $class = defined $object->class ? $object->class . ' ' : '';
        $class .= "$args{class}itemlabel";
        $object->class( $class );
    }

    # We're rendering this inline, so just render a UL (and any submenus as normal)
    if ( $self->render_children_inline ) {
        $buffer .= ( $args{'first'} ? '<ul class="first-of-type">' : '<ul>' );
        for my $kid ( @kids ) {
            $buffer .= ( qq(<li class="$args{class}item ) . ($kid->active? 'active' : '') . '">');
            $buffer .= $kid->as_link ;
            $buffer .= $kid->_render_as_yui_menu_item( class => 'yuimenu' );
            $buffer .= qq{</li>};
        }
        $buffer .= '</ul>';
    }
    # Render as normal submenus
    else {
       $buffer .= 
            qq{<div}
            . ($args{'id'} ? qq( id="$args{'id'}") : "")
            . qq( class="$args{class}"><div class="bd">);

        my $count    = 1;
        my $count_h6 = 1;
        my $openlist = 0;

        for my $kid ( @kids ) {
            # We want to render the children of this child inline, so close
            # any open <ul>s, render it as an <h6>, and then render it's
            # children.
            if ( $kid->render_children_inline and $kid->children ) {
                $buffer .= '</ul>' if $openlist;
                
                my @classes = ();
                push @classes, 'active' if $kid->active;
                push @classes, 'first-of-type'
                    if $count_h6 == 1 and $count == 1;

                $buffer .=        qq(<h6 class="@{[ join ' ', @classes ]}">)
                    .$kid->as_link .
                    '</h6>';
                $buffer .= $kid->_render_as_yui_menu_item(
                    class => 'yuimenu',
                    first => ($count == 1 ? 1 : 0)
                );
                $openlist = 0;
                $count_h6++;
            }
            # It's a normal child
            else {
                if ( not $openlist ) {
                   $buffer .=  ( $count == 1 ? '<ul class="first-of-type">' : '<ul>' );
                    $openlist = 1;
                }
                $buffer .= ( qq(<li class="$args{class}item ) . ($kid->active? 'active' : '') . '">');
                $buffer .= ( $kid->as_link );
                $buffer .= $kid->_render_as_yui_menu_item( class => 'yuimenu' );
                $buffer .= qq{</li>};
            }
            $count++;
        }
        $buffer .= '</ul>' if $openlist;
        $buffer .=qq{</div></div>};
    }
    return $buffer;
}

=head2 as_link

Return this menu item as a C<Jifty::Web::Link>, either the one we were
initialized with or a new one made from the C</label> and C</url>

If there's no C</url> and no C</link>, renders just the label.

=cut

sub as_link {
    my $self = shift;

    if ( $self->url ) {
        my $label = $self->label;
         _escape_utf8(\$label) if ($self->escape_label);
        return
              qq{<a href="@{[$self->url]}"}
            . ( $self->target ? qq{ target="@{[$self->target]}" } : '' )
            . ( $self->class  ? qq{ class="@{[$self->class]}" }   : '' )
            . ">". $label 
            . '</a>'

            ;

    } else {
        return $self->label;
    }
}
sub _escape_utf8 {
    my $ref = shift;
    no warnings 'uninitialized';
    $$ref =~ s/&/&#38;/g;
    $$ref =~ s/</&lt;/g;
    $$ref =~ s/>/&gt;/g;
    $$ref =~ s/\(/&#40;/g;
    $$ref =~ s/\)/&#41;/g;
    $$ref =~ s/"/&#34;/g;
    $$ref =~ s/'/&#39;/g;
}

1;
