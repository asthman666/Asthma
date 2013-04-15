use utf8;
package Asthma::Schema::Result::112ItemUrl;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Asthma::Schema::Result::112ItemUrl

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<112_item_url>

=cut

__PACKAGE__->table("112_item_url");

=head1 ACCESSORS

=head2 item_url_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
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

=head2 link

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 1024

=head2 md5_link

  data_type: 'char'
  default_value: (empty string)
  is_nullable: 0
  size: 22

=cut

__PACKAGE__->add_columns(
  "item_url_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
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
  "link",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 1024 },
  "md5_link",
  { data_type => "char", default_value => "", is_nullable => 0, size => 22 },
);

=head1 PRIMARY KEY

=over 4

=item * L</item_url_id>

=back

=cut

__PACKAGE__->set_primary_key("item_url_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<md5_link>

=over 4

=item * L</md5_link>

=back

=cut

__PACKAGE__->add_unique_constraint("md5_link", ["md5_link"]);


# Created by DBIx::Class::Schema::Loader v0.07017 @ 2013-04-15 14:50:20
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sFP/WivI8xzGqgDbsqXJpA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
