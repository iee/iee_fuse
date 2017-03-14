CREATE SEQUENCE gantt_links_seq
  INCREMENT 1
  START 5000
  CACHE 1;

CREATE TABLE "gantt_links" (
  "id" bigint primary key DEFAULT nextval('gantt_links_seq'),
  "source" bigint  NOT NULL,
  "target" bigint NOT NULL,
  "type" varchar(1) NOT NULL
);

CREATE SEQUENCE gantt_tasks_seq
  INCREMENT 1
  START 5000
  CACHE 1; 

CREATE TABLE "gantt_tasks" (
  "id" bigint primary key DEFAULT nextval('gantt_tasks_seq'),
  "text" varchar(255) NOT NULL,
  "start_date" timestamp with time zone NOT NULL,
  "duration" bigint NOT NULL,
  "progress" float DEFAULT 0 NOT NULL,
  "sortorder" bigint NOT NULL,
  "parent" bigint NOT NULL,
  "site_id" bigint NOT NULL,
  "definition" varchar(2048),
  "type" varchar(255) NOT NULL,
  "org_id" bigint references organization_ (organizationid),
  "contract" varchar(255),
  "status" varchar(1) NOT NULL,
  "folder_id" bigint NOT NULL
);

CREATE TABLE "gantt_roles" (
  "role_id" bigint primary key,
  "role_type" int NOT NULL,
  "role_name" varchar(255) NOT NULL
);

CREATE SEQUENCE gantt_tasks_users_seq
  INCREMENT 1
  START 5000
  CACHE 1;

CREATE TABLE "gantt_tasks_users" (
  "id" bigint primary key DEFAULT nextval('gantt_tasks_users_seq'),
  "gantt_task_id" bigint references gantt_tasks (id) NOT NULL,
  "user_id" bigint references user_ (userid) NOT NULL,
  "role_id" bigint references gantt_roles (role_id) NOT NULL,
  "responsible" boolean DEFAULT false NOT NULL
);

CREATE SEQUENCE gantt_finance_seq
  INCREMENT 1
  START 5000
  CACHE 1;

CREATE TABLE "gantt_finance" (
  "id" bigint primary key DEFAULT nextval('gantt_finance_seq'),
  "gantt_task_id" bigint references gantt_tasks (id) NOT NULL,
  "sum" numeric DEFAULT 0.00 NOT NULL
);

CREATE TABLE "gantt_finance_status" (
  "id" bigint primary key DEFAULT nextval('gantt_finance_seq'),
  "gantt_finance_id" bigint references gantt_finance (id) NOT NULL,
  "status" int
);
 
insert into gantt_roles(role_id, role_type, role_name) values
(1, 0, 'Администратор'),
(2, 0, 'Наблюдающий'),
(3, 0, 'Участник'),
(4, 1, 'Исполнитель'),
(5, 1, 'Контролёр');
