-- Mase Workspace: phase-one schema and row-level security.
-- Apply with the Supabase CLI or paste into the Supabase SQL editor as project owner.

create extension if not exists pgcrypto;

create type public.workspace_role as enum ('admin', 'client', 'collaborator');
create type public.idea_status as enum ('new_idea', 'discussing', 'approved', 'ready_to_film', 'filmed', 'editing', 'awaiting_approval', 'scheduled', 'published', 'archived');
create type public.content_format as enum ('reel', 'tiktok', 'photograph', 'carousel', 'story', 'youtube_video', 'testimonial', 'promotional_graphic', 'behind_the_scenes', 'video', 'other');
create type public.priority_level as enum ('low', 'normal', 'high', 'urgent');
create type public.approval_status as enum ('draft', 'awaiting_approval', 'approved', 'changes_requested');
create type public.request_status as enum ('new', 'accepted', 'needs_more_information', 'added_to_pipeline', 'outside_package', 'additional_charge_required', 'completed', 'declined');
create type public.file_visibility as enum ('client', 'collaborator', 'admin');
create type public.approval_scope as enum ('caption', 'final_content');
create type public.calendar_event_type as enum ('idea', 'filming', 'deadline', 'scheduled_post', 'meeting', 'other');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  avatar_url text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  industry text,
  logo_path text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.organisation_members (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.workspace_role not null default 'client',
  created_at timestamptz not null default now(),
  primary key (organisation_id, user_id)
);

create table public.client_profiles (
  organisation_id uuid primary key references public.organisations(id) on delete cascade,
  contact_name text,
  contact_email text,
  website text,
  instagram text,
  brand_notes text,
  content_goals text,
  updated_at timestamptz not null default now()
);

create table public.ideas (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 180),
  description text not null default '',
  objective text,
  promotion_subject text,
  suggested_hook text,
  audience text,
  key_message text,
  call_to_action text,
  format public.content_format not null default 'reel',
  platforms text[] not null default '{}',
  status public.idea_status not null default 'new_idea',
  priority public.priority_level not null default 'normal',
  filming_location text,
  filming_notes text,
  people_required text[] not null default '{}',
  equipment_props text,
  reference_url text,
  additional_notes text,
  target_date date,
  proposed_filming_date timestamptz,
  proposed_publish_date timestamptz,
  publish_date timestamptz,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.idea_assignees (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (idea_id, user_id)
);

create table public.idea_comments (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id),
  parent_id uuid references public.idea_comments(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  reactions jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.private_admin_notes (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid references public.ideas(id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles(id),
  body text not null check (char_length(body) between 1 and 8000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.idea_activity (
  id bigint generated always as identity primary key,
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  actor_id uuid references public.profiles(id),
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid references public.ideas(id) on delete set null,
  title text not null,
  platform text,
  format public.content_format not null default 'reel',
  caption text not null default '',
  hashtags text not null default '',
  asset_path text,
  thumbnail_path text,
  draft_url text,
  caption_approval_status public.approval_status not null default 'draft',
  final_approval_status public.approval_status not null default 'draft',
  approval_status public.approval_status not null default 'draft',
  scheduled_at timestamptz,
  published_url text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.captions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  content_item_id uuid not null references public.content_items(id) on delete cascade,
  version integer not null default 1 check (version > 0),
  body text not null default '',
  hashtags text not null default '',
  approval_status public.approval_status not null default 'draft',
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (content_item_id, version)
);

create table public.approvals (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  content_item_id uuid not null references public.content_items(id) on delete cascade,
  reviewer_id uuid not null default auth.uid() references public.profiles(id),
  scope public.approval_scope not null default 'final_content',
  status public.approval_status not null check (status in ('approved', 'changes_requested')),
  feedback text not null default '',
  created_at timestamptz not null default now()
);

create table public.filming_sessions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  title text not null,
  location text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  notes text,
  attendees text[] not null default '{}',
  equipment_checklist jsonb not null default '[]'::jsonb,
  props_required text,
  estimated_minutes integer check (estimated_minutes > 0),
  completed_at timestamptz,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.filming_session_ideas (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  session_id uuid not null references public.filming_sessions(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  sort_order integer not null default 0,
  primary key (session_id, idea_id)
);

create table public.shot_list_items (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  session_id uuid references public.filming_sessions(id) on delete set null,
  description text not null,
  note text,
  reference_path text,
  completed boolean not null default false,
  completed_at timestamptz,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  title text not null,
  event_type public.calendar_event_type not null default 'other',
  starts_at timestamptz not null,
  ends_at timestamptz,
  idea_id uuid references public.ideas(id) on delete cascade,
  notes text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.client_requests (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  title text not null,
  description text not null,
  request_type text not null default 'general_content_request',
  requested_deadline timestamptz,
  contact_person text,
  priority public.priority_level not null default 'normal',
  status public.request_status not null default 'new',
  requested_by uuid not null default auth.uid() references public.profiles(id),
  admin_response text,
  due_date date,
  outside_package boolean not null default false,
  additional_charge_required boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.analytics_periods (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  period_start date not null,
  period_end date not null check (period_end >= period_start),
  summary text,
  wins text,
  struggled text,
  opportunities text,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, period_start, period_end)
);

create table public.account_metrics (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  analytics_period_id uuid references public.analytics_periods(id) on delete cascade,
  platform text not null,
  followers integer check (followers >= 0),
  followers_gained integer,
  reach integer check (reach >= 0),
  views integer check (views >= 0),
  impressions integer check (impressions >= 0),
  non_followers_reached integer check (non_followers_reached >= 0),
  engagement_count integer check (engagement_count >= 0),
  engagement_rate numeric(7,3) check (engagement_rate >= 0),
  profile_visits integer check (profile_visits >= 0),
  website_clicks integer check (website_clicks >= 0),
  website_actions integer check (website_actions >= 0),
  calls integer check (calls >= 0),
  messages integer check (messages >= 0),
  enquiries integer check (enquiries >= 0),
  bookings integer check (bookings >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.post_metrics (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  analytics_period_id uuid references public.analytics_periods(id) on delete cascade,
  content_item_id uuid references public.content_items(id) on delete set null,
  platform text not null,
  title text not null,
  published_at timestamptz,
  views integer check (views >= 0),
  reach integer check (reach >= 0),
  impressions integer check (impressions >= 0),
  likes integer check (likes >= 0),
  comments integer check (comments >= 0),
  saves integer check (saves >= 0),
  shares integer check (shares >= 0),
  watch_time_seconds integer check (watch_time_seconds >= 0),
  completion_rate numeric(7,3) check (completion_rate >= 0),
  engagement_rate numeric(7,3) check (engagement_rate >= 0),
  post_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.posting_time_recommendations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  platform text not null,
  weekday smallint not null check (weekday between 0 and 6),
  hour smallint not null check (hour between 0 and 23),
  score numeric(7,3) not null default 0,
  note text,
  updated_at timestamptz not null default now(),
  unique (organisation_id, platform, weekday, hour)
);

create table public.workspace_files (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes >= 0),
  visibility public.file_visibility not null default 'client',
  category text not null default 'general',
  uploaded_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  check (storage_path like organisation_id::text || '/%')
);

create table public.idea_attachments (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  idea_id uuid not null references public.ideas(id) on delete cascade,
  workspace_file_id uuid not null references public.workspace_files(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.request_attachments (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  request_id uuid not null references public.client_requests(id) on delete cascade,
  workspace_file_id uuid not null references public.workspace_files(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.client_briefs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null unique references public.organisations(id) on delete cascade,
  business_overview text,
  audience text,
  tone_of_voice text,
  visual_direction text,
  main_services text,
  goals text,
  content_pillars text[],
  do_list text,
  avoid_list text,
  links jsonb not null default '{}'::jsonb,
  contact_details text,
  brand_colours text,
  brand_fonts text,
  important_dates text,
  regular_offers text,
  calls_to_action text,
  approval_contacts text,
  monthly_deliverables text,
  updated_by uuid default auth.uid() references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  organisation_id uuid references public.organisations(id) on delete cascade,
  title text not null,
  body text not null,
  href text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- Composite relationships prevent a child record from claiming one organisation
-- while pointing at a parent record in another organisation.
alter table public.ideas add constraint ideas_id_org_unique unique (id, organisation_id);
alter table public.content_items add constraint content_items_id_org_unique unique (id, organisation_id);
alter table public.filming_sessions add constraint filming_sessions_id_org_unique unique (id, organisation_id);
alter table public.analytics_periods add constraint analytics_periods_id_org_unique unique (id, organisation_id);
alter table public.workspace_files add constraint workspace_files_id_org_unique unique (id, organisation_id);
alter table public.client_requests add constraint client_requests_id_org_unique unique (id, organisation_id);
alter table public.captions add constraint captions_content_org_fk foreign key (content_item_id, organisation_id) references public.content_items(id, organisation_id) on delete cascade;
alter table public.idea_assignees add constraint idea_assignees_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.idea_comments add constraint idea_comments_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.private_admin_notes add constraint private_notes_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.idea_activity add constraint idea_activity_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.content_items add constraint content_items_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.approvals add constraint approvals_content_org_fk foreign key (content_item_id, organisation_id) references public.content_items(id, organisation_id) on delete cascade;
alter table public.filming_session_ideas add constraint filming_session_ideas_session_org_fk foreign key (session_id, organisation_id) references public.filming_sessions(id, organisation_id) on delete cascade;
alter table public.filming_session_ideas add constraint filming_session_ideas_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.shot_list_items add constraint shots_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.shot_list_items add constraint shots_session_org_fk foreign key (session_id, organisation_id) references public.filming_sessions(id, organisation_id) on delete cascade;
alter table public.calendar_events add constraint events_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.account_metrics add constraint account_metrics_period_org_fk foreign key (analytics_period_id, organisation_id) references public.analytics_periods(id, organisation_id) on delete cascade;
alter table public.post_metrics add constraint post_metrics_period_org_fk foreign key (analytics_period_id, organisation_id) references public.analytics_periods(id, organisation_id) on delete cascade;
alter table public.post_metrics add constraint post_metrics_content_org_fk foreign key (content_item_id, organisation_id) references public.content_items(id, organisation_id) on delete cascade;
alter table public.idea_attachments add constraint attachments_idea_org_fk foreign key (idea_id, organisation_id) references public.ideas(id, organisation_id) on delete cascade;
alter table public.idea_attachments add constraint attachments_file_org_fk foreign key (workspace_file_id, organisation_id) references public.workspace_files(id, organisation_id) on delete cascade;
alter table public.request_attachments add constraint request_attachments_request_org_fk foreign key (request_id, organisation_id) references public.client_requests(id, organisation_id) on delete cascade;
alter table public.request_attachments add constraint request_attachments_file_org_fk foreign key (workspace_file_id, organisation_id) references public.workspace_files(id, organisation_id) on delete cascade;

-- The composite keys above replace the original single-column relationships.
-- Removing the redundant keys keeps PostgREST relationship embedding unambiguous.
alter table public.captions drop constraint captions_content_item_id_fkey;
alter table public.idea_assignees drop constraint idea_assignees_idea_id_fkey;
alter table public.idea_comments drop constraint idea_comments_idea_id_fkey;
alter table public.private_admin_notes drop constraint private_admin_notes_idea_id_fkey;
alter table public.idea_activity drop constraint idea_activity_idea_id_fkey;
alter table public.content_items drop constraint content_items_idea_id_fkey;
alter table public.approvals drop constraint approvals_content_item_id_fkey;
alter table public.filming_session_ideas drop constraint filming_session_ideas_session_id_fkey;
alter table public.filming_session_ideas drop constraint filming_session_ideas_idea_id_fkey;
alter table public.shot_list_items drop constraint shot_list_items_idea_id_fkey;
alter table public.shot_list_items drop constraint shot_list_items_session_id_fkey;
alter table public.calendar_events drop constraint calendar_events_idea_id_fkey;
alter table public.account_metrics drop constraint account_metrics_analytics_period_id_fkey;
alter table public.post_metrics drop constraint post_metrics_analytics_period_id_fkey;
alter table public.post_metrics drop constraint post_metrics_content_item_id_fkey;
alter table public.idea_attachments drop constraint idea_attachments_idea_id_fkey;
alter table public.idea_attachments drop constraint idea_attachments_workspace_file_id_fkey;
alter table public.request_attachments drop constraint request_attachments_request_id_fkey;
alter table public.request_attachments drop constraint request_attachments_workspace_file_id_fkey;

create index ideas_org_status_idx on public.ideas (organisation_id, status, updated_at desc);
create index comments_idea_idx on public.idea_comments (idea_id, created_at);
create index content_org_approval_idx on public.content_items (organisation_id, approval_status, updated_at desc);
create index events_org_start_idx on public.calendar_events (organisation_id, starts_at);
create index sessions_org_start_idx on public.filming_sessions (organisation_id, starts_at);
create index requests_org_status_idx on public.client_requests (organisation_id, status, updated_at desc);
create index files_org_created_idx on public.workspace_files (organisation_id, created_at desc);
create index notifications_user_idx on public.notifications (user_id, read_at, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.protect_organisation_id()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.organisation_id is distinct from old.organisation_id then
    raise exception 'organisation_id cannot be changed';
  end if;
  return new;
end;
$$;

create or replace function public.protect_file_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.organisation_id is distinct from old.organisation_id
    or new.storage_path is distinct from old.storage_path
    or new.uploaded_by is distinct from old.uploaded_by then
    raise exception 'File identity cannot be changed';
  end if;
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'profiles','organisations','client_profiles','ideas','idea_comments','private_admin_notes',
    'content_items','captions','filming_sessions','shot_list_items','calendar_events','client_requests',
    'analytics_periods','account_metrics','post_metrics','posting_time_recommendations','client_briefs'
  ] loop
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'client_profiles','ideas','idea_assignees','idea_comments','private_admin_notes','idea_activity',
    'content_items','captions','approvals','filming_sessions','filming_session_ideas','shot_list_items',
    'calendar_events','client_requests','analytics_periods','account_metrics','post_metrics',
    'posting_time_recommendations','idea_attachments','request_attachments','client_briefs'
  ] loop
    execute format('create trigger %I_protect_organisation before update on public.%I for each row execute function public.protect_organisation_id()', table_name, table_name);
  end loop;
end $$;
create trigger workspace_files_protect_identity before update on public.workspace_files for each row execute function public.protect_file_identity();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid());
$$;

create or replace function public.is_org_member(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_platform_admin() or exists (
    select 1 from public.organisation_members
    where organisation_id = target_org and user_id = auth.uid()
  );
$$;

create or replace function public.current_org_role(target_org uuid)
returns public.workspace_role language sql stable security definer set search_path = '' as $$
  select case when public.is_platform_admin() then 'admin'::public.workspace_role else (
    select role from public.organisation_members
    where organisation_id = target_org and user_id = auth.uid()
  ) end;
$$;

create or replace function public.can_manage_org(target_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_platform_admin() or exists (
    select 1 from public.organisation_members
    where organisation_id = target_org and user_id = auth.uid() and role in ('admin', 'collaborator')
  );
$$;

create or replace function public.review_content(target_content uuid, review_scope public.approval_scope, decision public.approval_status, review_feedback text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare
  target_org uuid;
  current_caption_status public.approval_status;
  current_final_status public.approval_status;
begin
  if decision not in ('approved'::public.approval_status, 'changes_requested'::public.approval_status) then
    raise exception 'Invalid approval decision';
  end if;
  select organisation_id, caption_approval_status, final_approval_status
  into target_org, current_caption_status, current_final_status
  from public.content_items
  where id = target_content
  for update;
  if target_org is null
    or not public.is_org_member(target_org)
    or public.current_org_role(target_org) = 'collaborator'::public.workspace_role then
    raise exception 'Content is unavailable for review';
  end if;
  if (review_scope = 'caption'::public.approval_scope and current_caption_status <> 'awaiting_approval'::public.approval_status)
    or (review_scope = 'final_content'::public.approval_scope and current_final_status <> 'awaiting_approval'::public.approval_status) then
    raise exception 'That part of the content is not awaiting approval';
  end if;
  insert into public.approvals (organisation_id, content_item_id, reviewer_id, scope, status, feedback)
  values (target_org, target_content, auth.uid(), review_scope, decision, coalesce(review_feedback, ''));
  if review_scope = 'caption'::public.approval_scope then
    update public.content_items set caption_approval_status = decision where id = target_content;
    update public.captions set approval_status = decision
    where id = (
      select id from public.captions
      where content_item_id = target_content
      order by version desc
      limit 1
    );
  else
    update public.content_items set final_approval_status = decision where id = target_content;
  end if;
  update public.content_items
  set approval_status = case
    when caption_approval_status = 'changes_requested' or final_approval_status = 'changes_requested' then 'changes_requested'::public.approval_status
    when caption_approval_status = 'approved' and final_approval_status = 'approved' then 'approved'::public.approval_status
    else 'awaiting_approval'::public.approval_status
  end
  where id = target_content;
end;
$$;

create or replace function public.react_to_comment(target_comment uuid, reaction text)
returns void language plpgsql security definer set search_path = '' as $$
declare target_org uuid;
begin
  if reaction not in ('useful', 'like', 'seen') then raise exception 'Invalid reaction'; end if;
  select organisation_id into target_org from public.idea_comments where id = target_comment;
  if target_org is null or not public.is_org_member(target_org) then raise exception 'Comment is unavailable'; end if;
  update public.idea_comments set reactions = jsonb_set(
    coalesce(reactions, '{}'::jsonb), array[reaction],
    to_jsonb(coalesce((reactions ->> reaction)::integer, 0) + 1), true
  ) where id = target_comment;
end;
$$;

create or replace function public.resolve_comment(target_comment uuid, resolved boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare target_org uuid; target_author uuid;
begin
  select organisation_id, author_id into target_org, target_author from public.idea_comments where id = target_comment;
  if target_org is null or not public.is_org_member(target_org) or not (public.can_manage_org(target_org) or target_author = auth.uid()) then
    raise exception 'Comment cannot be changed';
  end if;
  update public.idea_comments set resolved_at = case when resolved then now() else null end where id = target_comment;
end;
$$;

revoke all on function public.is_platform_admin() from public;
revoke all on function public.is_org_member(uuid) from public;
revoke all on function public.current_org_role(uuid) from public;
revoke all on function public.can_manage_org(uuid) from public;
revoke all on function public.review_content(uuid, public.approval_scope, public.approval_status, text) from public;
revoke all on function public.react_to_comment(uuid, text) from public;
revoke all on function public.resolve_comment(uuid, boolean) from public;
grant execute on function public.is_platform_admin(), public.is_org_member(uuid), public.current_org_role(uuid), public.can_manage_org(uuid), public.review_content(uuid, public.approval_scope, public.approval_status, text), public.react_to_comment(uuid, text), public.resolve_comment(uuid, boolean) to authenticated;

create or replace function public.log_idea_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.idea_activity (organisation_id, idea_id, actor_id, action, details)
    values (new.organisation_id, new.id, auth.uid(), 'idea_created', jsonb_build_object('status', new.status));
  elsif old.status is distinct from new.status then
    insert into public.idea_activity (organisation_id, idea_id, actor_id, action, details)
    values (new.organisation_id, new.id, auth.uid(), 'status_changed', jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end;
$$;
create trigger ideas_log_activity after insert or update on public.ideas for each row execute function public.log_idea_activity();

create or replace function public.log_comment_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.idea_activity (organisation_id, idea_id, actor_id, action, details)
  values (new.organisation_id, new.idea_id, new.author_id, 'comment_added', jsonb_build_object('comment_id', new.id));
  return new;
end;
$$;
create trigger comments_log_activity after insert on public.idea_comments for each row execute function public.log_comment_activity();

create or replace function public.log_approval_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target_idea uuid;
begin
  select idea_id into target_idea from public.content_items where id = new.content_item_id;
  if target_idea is not null then
    insert into public.idea_activity (organisation_id, idea_id, actor_id, action, details)
    values (new.organisation_id, target_idea, new.reviewer_id,
      case when new.status = 'approved' then new.scope::text || '_approved' else new.scope::text || '_changes_requested' end,
      jsonb_build_object('approval_id', new.id));
  end if;
  return new;
end;
$$;
create trigger approvals_log_activity after insert on public.approvals for each row execute function public.log_approval_activity();

create or replace function public.sync_content_idea_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.idea_id is null then return new; end if;
  if new.published_url is not null then
    update public.ideas set status = 'published', publish_date = coalesce(new.scheduled_at, now()) where id = new.idea_id;
  elsif new.scheduled_at is not null and new.final_approval_status = 'approved' then
    update public.ideas set status = 'scheduled', publish_date = new.scheduled_at where id = new.idea_id;
  elsif new.approval_status = 'awaiting_approval' then
    update public.ideas set status = 'awaiting_approval' where id = new.idea_id and status <> 'published';
  end if;
  return new;
end;
$$;
create trigger content_sync_idea_status after insert or update on public.content_items for each row execute function public.sync_content_idea_status();

alter table public.profiles enable row level security;
alter table public.app_admins enable row level security;
alter table public.organisations enable row level security;
alter table public.organisation_members enable row level security;
alter table public.client_profiles enable row level security;
alter table public.ideas enable row level security;
alter table public.idea_assignees enable row level security;
alter table public.idea_comments enable row level security;
alter table public.private_admin_notes enable row level security;
alter table public.idea_activity enable row level security;
alter table public.content_items enable row level security;
alter table public.captions enable row level security;
alter table public.approvals enable row level security;
alter table public.filming_sessions enable row level security;
alter table public.filming_session_ideas enable row level security;
alter table public.shot_list_items enable row level security;
alter table public.calendar_events enable row level security;
alter table public.client_requests enable row level security;
alter table public.analytics_periods enable row level security;
alter table public.account_metrics enable row level security;
alter table public.post_metrics enable row level security;
alter table public.posting_time_recommendations enable row level security;
alter table public.workspace_files enable row level security;
alter table public.idea_attachments enable row level security;
alter table public.request_attachments enable row level security;
alter table public.client_briefs enable row level security;
alter table public.notifications enable row level security;

create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid() or public.is_platform_admin() or exists (
    select 1 from public.organisation_members mine join public.organisation_members theirs using (organisation_id)
    where mine.user_id = auth.uid() and theirs.user_id = profiles.id
  )
);
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy app_admins_select_self on public.app_admins for select to authenticated using (user_id = auth.uid());
create policy organisations_select on public.organisations for select to authenticated using (public.is_org_member(id));
create policy organisations_admin_all on public.organisations for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy memberships_select on public.organisation_members for select to authenticated using (public.is_org_member(organisation_id));
create policy memberships_admin_all on public.organisation_members for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy client_profiles_select on public.client_profiles for select to authenticated using (public.is_org_member(organisation_id));
create policy client_profiles_manage on public.client_profiles for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));

create policy ideas_select on public.ideas for select to authenticated using (public.is_org_member(organisation_id));
create policy ideas_insert on public.ideas for insert to authenticated with check (public.is_org_member(organisation_id) and created_by = auth.uid());
create policy ideas_update_team on public.ideas for update to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy ideas_update_client on public.ideas for update to authenticated using (
  public.current_org_role(organisation_id) = 'client' and created_by = auth.uid() and status in ('new_idea','discussing')
) with check (
  public.current_org_role(organisation_id) = 'client' and created_by = auth.uid() and status in ('new_idea','discussing')
);
create policy ideas_delete_admin on public.ideas for delete to authenticated using (public.is_platform_admin());

create policy assignees_select on public.idea_assignees for select to authenticated using (public.is_org_member(organisation_id));
create policy assignees_manage on public.idea_assignees for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy comments_select on public.idea_comments for select to authenticated using (public.is_org_member(organisation_id));
create policy comments_insert on public.idea_comments for insert to authenticated with check (public.is_org_member(organisation_id) and author_id = auth.uid());
create policy comments_update on public.idea_comments for update to authenticated using (author_id = auth.uid() or public.can_manage_org(organisation_id)) with check (author_id = auth.uid() or public.can_manage_org(organisation_id));
create policy comments_delete on public.idea_comments for delete to authenticated using (author_id = auth.uid() or public.is_platform_admin());
create policy notes_admin_all on public.private_admin_notes for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy activity_select on public.idea_activity for select to authenticated using (public.is_org_member(organisation_id));

create policy content_select on public.content_items for select to authenticated using (
  public.can_manage_org(organisation_id) or (public.is_org_member(organisation_id) and approval_status <> 'draft')
);
create policy content_manage on public.content_items for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy captions_select on public.captions for select to authenticated using (
  public.can_manage_org(organisation_id) or (public.is_org_member(organisation_id) and approval_status <> 'draft')
);
create policy captions_manage on public.captions for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy approvals_select on public.approvals for select to authenticated using (public.is_org_member(organisation_id));

create policy sessions_select on public.filming_sessions for select to authenticated using (public.is_org_member(organisation_id));
create policy sessions_manage on public.filming_sessions for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy session_ideas_select on public.filming_session_ideas for select to authenticated using (public.is_org_member(organisation_id));
create policy session_ideas_manage on public.filming_session_ideas for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy shots_select on public.shot_list_items for select to authenticated using (public.is_org_member(organisation_id));
create policy shots_manage on public.shot_list_items for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));

create policy events_select on public.calendar_events for select to authenticated using (public.is_org_member(organisation_id));
create policy events_manage on public.calendar_events for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy requests_select on public.client_requests for select to authenticated using (public.is_org_member(organisation_id));
create policy requests_insert on public.client_requests for insert to authenticated with check (public.is_org_member(organisation_id) and requested_by = auth.uid());
create policy requests_manage on public.client_requests for update to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy requests_update_own on public.client_requests for update to authenticated using (requested_by = auth.uid() and status = 'new') with check (requested_by = auth.uid() and status = 'new');

create policy analytics_periods_select on public.analytics_periods for select to authenticated using (public.is_org_member(organisation_id));
create policy analytics_periods_manage on public.analytics_periods for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy account_metrics_select on public.account_metrics for select to authenticated using (public.is_org_member(organisation_id));
create policy account_metrics_manage on public.account_metrics for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy post_metrics_select on public.post_metrics for select to authenticated using (public.is_org_member(organisation_id));
create policy post_metrics_manage on public.post_metrics for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy recommendations_select on public.posting_time_recommendations for select to authenticated using (public.is_org_member(organisation_id));
create policy recommendations_manage on public.posting_time_recommendations for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));

create policy files_select on public.workspace_files for select to authenticated using (
  public.is_platform_admin() or (
    public.is_org_member(organisation_id) and (
      visibility = 'client' or
      (visibility = 'collaborator' and public.current_org_role(organisation_id) in ('admin','collaborator')) or
      (visibility = 'admin' and public.current_org_role(organisation_id) = 'admin')
    )
  )
);
create policy files_insert on public.workspace_files for insert to authenticated with check (
  public.is_org_member(organisation_id) and uploaded_by = auth.uid() and
  (visibility = 'client' or public.can_manage_org(organisation_id))
);
create policy files_update on public.workspace_files for update to authenticated using (uploaded_by = auth.uid() or public.can_manage_org(organisation_id)) with check (public.is_org_member(organisation_id) and (uploaded_by = auth.uid() or public.can_manage_org(organisation_id)));
create policy files_delete on public.workspace_files for delete to authenticated using (uploaded_by = auth.uid() or public.is_platform_admin());
create policy attachments_select on public.idea_attachments for select to authenticated using (public.is_org_member(organisation_id));
create policy attachments_insert on public.idea_attachments for insert to authenticated with check (public.is_org_member(organisation_id));
create policy attachments_delete on public.idea_attachments for delete to authenticated using (public.can_manage_org(organisation_id));
create policy request_attachments_select on public.request_attachments for select to authenticated using (public.is_org_member(organisation_id));
create policy request_attachments_insert on public.request_attachments for insert to authenticated with check (public.is_org_member(organisation_id));
create policy request_attachments_delete on public.request_attachments for delete to authenticated using (public.can_manage_org(organisation_id));

create policy briefs_select on public.client_briefs for select to authenticated using (public.is_org_member(organisation_id));
create policy briefs_manage on public.client_briefs for all to authenticated using (public.can_manage_org(organisation_id)) with check (public.can_manage_org(organisation_id));
create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_admin_insert on public.notifications for insert to authenticated with check (public.is_platform_admin());

insert into storage.buckets (id, name, public, file_size_limit)
values ('workspace', 'workspace', false, 104857600)
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit;

create policy workspace_objects_select on storage.objects for select to authenticated using (
  bucket_id = 'workspace' and exists (
    select 1 from public.workspace_files f
    where f.storage_path = name and f.archived_at is null and (
      public.is_platform_admin() or (
        public.is_org_member(f.organisation_id) and (
          f.visibility = 'client' or
          (f.visibility = 'collaborator' and public.current_org_role(f.organisation_id) in ('admin','collaborator')) or
          (f.visibility = 'admin' and public.current_org_role(f.organisation_id) = 'admin')
        )
      )
    )
  )
);
create policy workspace_objects_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'workspace' and exists (
    select 1 from public.workspace_files f
    where f.storage_path = name and f.uploaded_by = auth.uid() and public.is_org_member(f.organisation_id)
  )
);
create policy workspace_objects_update on storage.objects for update to authenticated using (
  bucket_id = 'workspace' and exists (
    select 1 from public.workspace_files f where f.storage_path = name and (f.uploaded_by = auth.uid() or public.can_manage_org(f.organisation_id))
  )
) with check (
  bucket_id = 'workspace' and exists (
    select 1 from public.workspace_files f
    where f.storage_path = name and (f.uploaded_by = auth.uid() or public.can_manage_org(f.organisation_id))
  )
);
create policy workspace_objects_delete on storage.objects for delete to authenticated using (
  bucket_id = 'workspace' and exists (
    select 1 from public.workspace_files f where f.storage_path = name and (f.uploaded_by = auth.uid() or public.is_platform_admin())
  )
);

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
