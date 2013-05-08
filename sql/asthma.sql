drop table if exists load_list_url;
create table load_list_url (
    list_url_id     int unsigned     auto_increment,
    dt_created      datetime         default '0000-00-00 00:00:00' not null,
    dt_updated      datetime         default '0000-00-00 00:00:00' not null,
    link            varchar(1024)    default '' not null,
    md5_link        char(22) binary  default '' not null,
    primary key (list_url_id),
    unique key (md5_link)
) engine=myisam;

drop table if exists load_item_url;
create table load_item_url (
    item_url_id     int unsigned     auto_increment,
    dt_created      datetime         default '0000-00-00 00:00:00' not null,
    dt_updated      datetime         default '0000-00-00 00:00:00' not null,
    link            varchar(1024)    default '' not null,
    md5_link        char(22) binary  default '' not null,
    primary key (item_url_id),
    unique key (md5_link)
) engine=myisam;

drop table if exists model;
create table model (
    model_id        int unsigned     auto_increment,
    dt_created      datetime         default '0000-00-00 00:00:00' not null,
    active          enum('y', 'n')   default 'y' not null, 
    dt_updated      datetime         default '0000-00-00 00:00:00' not null,
    value           varchar(255)     default '' not null,
    primary key (model_id),
    unique key value (value)
) engine=innodb;

drop table if exists site_browse;
create table site_browse (
    browse_id       bigint unsigned  default 0 not null,
    site_id         int unsigned  default 0  not null,

    value           varchar(255)  default '' not null,
    browse_tree     varchar(255)  default '' not null,
    browse_tree_value varchar(1024) default '' not null,

    active          enum('y', 'n') default 'y' not null,
    dt_created      datetime default '0000-00-00 00:00:00' not null,
    dt_updated      datetime default '0000-00-00 00:00:00' not null,

    level              tinyint unsigned default 0   not null,
    parent_browse_id   int unsigned default 0       not null,
    is_leaf            enum('y', 'n')  default 'n'  not null,
    primary key (browse_id, site_id),
    key is_leaf (is_leaf)
) engine = innodb;

