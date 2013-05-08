use utf8;
package Asthma::Schema::Result::SiteBrowse;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Asthma::Schema::Result::SiteBrowse

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<site_browse>

=cut

__PACKAGE__->table("site_browse");

=head1 ACCESSORS

=head2 browse_id

  data_type: 'bigint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 site_id

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 value

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 255

=head2 browse_tree

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 255

=head2 browse_tree_value

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 1024

=head2 active

  data_type: 'enum'
  default_value: 'y'
  extra: {list => ["y","n"]}
  is_nullable: 0

=head2 dt_created

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: '0000-00-00 00:00:00'
  is_nullable: 0

=head2 dt_updated

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  default_value: '0000-00-00 00:00:00'
  is_nullable: 0

=head2 level

  data_type: 'tinyint'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 parent_browse_id

  data_type: 'integer'
  default_value: 0
  extra: {unsigned => 1}
  is_nullable: 0

=head2 is_leaf

  data_type: 'enum'
  default_value: 'n'
  extra: {list => ["y","n"]}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "browse_id",
  {
    data_type => "bigint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "site_id",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "value",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 255 },
  "browse_tree",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 255 },
  "browse_tree_value",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 1024 },
  "active",
  {
    data_type => "enum",
    default_value => "y",
    extra => { list => ["y", "n"] },
    is_nullable => 0,
  },
  "dt_created",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "0000-00-00 00:00:00",
    is_nullable => 0,
  },
  "dt_updated",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    default_value => "0000-00-00 00:00:00",
    is_nullable => 0,
  },
  "level",
  {
    data_type => "tinyint",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "parent_browse_id",
  {
    data_type => "integer",
    default_value => 0,
    extra => { unsigned => 1 },
    is_nullable => 0,
  },
  "is_leaf",
  {
    data_type => "enum",
    default_value => "n",
    extra => { list => ["y", "n"] },
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</browse_id>

=item * L</site_id>

=back

=cut

__PACKAGE__->set_primary_key("browse_id", "site_id");


# Created by DBIx::Class::Schema::Loader v0.07017 @ 2013-05-08 14:53:38
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9GDNiimKU+KmftwohUaSvA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
