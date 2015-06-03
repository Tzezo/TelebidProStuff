use strict;
use warnings;

use Test::More tests => 7;
use DBEngine;
use Data::Dumper;

my $db = new DBEngine;

cmp_ok($db->CreateTable("test1", "id int, id2 int, id3 int, id4 int, id5 int, name text, name2 text, name3 text"), "==", 1);
ok($db->InsertIntoTable(undef, "test1", ("id=30002", "id2=5", "id3=100", "id4=8", "id5=5", "name=Test", "name2=TEst2", "name3=TEst343")));
ok($db->InsertIntoTable(undef, "test1", ("id=1", "id2=5", "id3=100", "id4=8", "id5=5", "name=Test", "name2=TEst2", "name3=TEst343")));
ok($db->Update("test1", "id=1", "name=LSFC"));
ok($db->Delete("test1", "id=1"));
ok($db->Select("test1", "id=30002", sub{}));
cmp_ok($db->CreateIndex("test1", "id"), "==", 1);

