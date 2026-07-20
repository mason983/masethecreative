-- Development-only sample organisations. Do not run this file in production.
-- Users are deliberately not seeded: invite real test accounts through Mase Workspace.
insert into public.organisations (id, name, slug, industry) values
  ('10000000-0000-4000-8000-000000000001', 'Fourwards', 'fourwards', 'Hospitality'),
  ('10000000-0000-4000-8000-000000000002', 'The Black Horse', 'the-black-horse', 'Hospitality'),
  ('10000000-0000-4000-8000-000000000003', 'ORE4x4', 'ore4x4', 'Automotive')
on conflict (slug) do nothing;

insert into public.client_profiles (organisation_id, contact_name, content_goals) values
  ('10000000-0000-4000-8000-000000000001', 'Fourwards team', 'Show the food, people and personality behind the restaurant.'),
  ('10000000-0000-4000-8000-000000000002', 'The Black Horse team', 'Build a recognisable local presence around food, events and atmosphere.'),
  ('10000000-0000-4000-8000-000000000003', 'ORE4x4 team', 'Explain capability, document builds and earn attention from enthusiasts.')
on conflict (organisation_id) do nothing;

insert into public.client_briefs (organisation_id, business_overview, audience, tone_of_voice, content_pillars) values
  ('10000000-0000-4000-8000-000000000001', 'Independent restaurant with an ingredient-led menu.', 'Local diners and destination food customers.', 'Warm, confident and human.', array['Food', 'People', 'Behind the scenes']),
  ('10000000-0000-4000-8000-000000000002', 'A characterful pub serving its local community.', 'Local regulars, families and weekend visitors.', 'Welcoming, straightforward and lively.', array['Food and drink', 'Events', 'Community']),
  ('10000000-0000-4000-8000-000000000003', 'Specialist off-road vehicle and engineering business.', '4x4 owners and automotive enthusiasts.', 'Knowledgeable, practical and energetic.', array['Builds', 'Technical expertise', 'Finished vehicles'])
on conflict (organisation_id) do nothing;

-- Example records omit created_by so they are best added after an admin test account exists.
