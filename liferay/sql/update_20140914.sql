CREATE SEQUENCE gantt_tasks_users_seq
  INCREMENT 1
  START 5000
  CACHE 1;
 
CREATE TABLE "gantt_roles" (
  "role_id" bigint primary key,
  "role_type" int NOT NULL,
  "role_name" varchar(255) NOT NULL
);

CREATE TABLE "gantt_tasks_users" (
  "id" bigint primary key DEFAULT nextval('gantt_tasks_users_seq'),
  "gantt_task_id" bigint references gantt_tasks (id) NOT NULL,
  "user_id" bigint references user_ (userid) NOT NULL,
  "role_id" bigint references gantt_roles (role_id) NOT NULL
);

insert into gantt_roles(role_id, role_type, role_name) values
(1, 0, 'Администратор'),
(2, 0, 'Наблюдающий'),
(3, 0, 'Участник'),
(4, 1, 'Исполнитель'),
(5, 1, 'Ответственный'),
(6, 1, 'Контролёр');
