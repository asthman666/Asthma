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
