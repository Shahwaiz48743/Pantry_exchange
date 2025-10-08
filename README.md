# Pantry_exchange
Database for neighborhood food sharing, expiry tracking, IoT logs &amp; token incentives


#Neighborhood Pantry Exchange & Waste-Trace DB

A production-grade relational schema for community food sharing and food-waste traceability.
It models households and users, an item catalog with instance-level expiry tracking, offers and requests matching, completed exchanges, token incentives, IoT sensor readings (e.g., fridge temperature), and audit logs for compliance and analysis.

#Summary

I designed and implemented a realistic database that supports a neighborhood pantry exchange: people can offer near-expiry items, request what they need, and complete exchanges while the system tracks traceability, incentives, and operational signals from sensors. The schema is optimized for clarity, integrity, and analytics.

#Why this matters

Reduces avoidable food waste by making near-expiry stock visible and actionable.

Encodes traceability from purchase to exchange, enabling audits and research.

Demonstrates practical data engineering choices you’d expect in production systems.

#What this demonstrates

Data modeling and normalization for a multi-entity domain.

Strong integrity via foreign keys, check constraints, and thoughtful cascade rules.

Advanced SQL proficiency: window functions, pivots/rollups, parameterized analytics, and geospatial-style proximity logic using Haversine.

Performance-minded indexing and query design.

Pragmatic handling of SQL Server’s multiple-cascade limitations.

#Key highlights

Item-instance traceability: batch, purchase date, estimated expiry, and storage guidance.

Marketplace flow: offers ↔ requests with clean matching and an exchanges ledger.

Incentive ledger: token transactions (earn/spend) for positive behaviors.

IoT telemetry: temperature, humidity, CO₂, and door events linked to households or item instances.

Auditability: structured event logs for state changes and waste reasons.

Analytics-ready: curated queries and views for KPIs, risk ranking, and proximity matches.

#Data model (at a glance)

Zones → Households → Users establish location and membership.

Items define the catalog; Item Instances represent real stock with expiry.

Offers and Requests express market intent; Exchanges capture outcomes.

Token Transactions reward participation.

Sensor Readings provide operational signals.

Audit Logs record lifecycle events and moderation/reporting.

#What’s included

Clean SQL Server schema and constraints.

Realistic seed data (30 rows per table) for instant exploration.

A professional query pack covering basic, intermediate, and advanced analytics.

Helpful views to speed up review (enriched offers, token balances, expiring items).

#How to review quickly

Start with the schema to see entity boundaries, keys, and constraints.

Skim the seed data to understand realistic values and relationships.

Run the query pack to view:

Newest user per zone (window functions).

Open-offer proximity suggestions (Haversine with APPLY).

Daily exchange KPIs (GROUPING SETS).

Token balances and user activity summaries.

Design decisions & trade-offs

Cascades: only one delete cascade on the critical path; other relationships use SET NULL or NO ACTION to avoid multiple-cascade conflicts in SQL Server.

Enumerations: modeled with constrained text (check constraints) for portability.

Time: UTC storage for consistency across regions.

Indexes: targeted to common filters (e.g., status + validity, expiry + state) and joins on foreign keys.

JSON detail: stored as text for flexibility; can be validated when required.

Example analytics (no code, just outcomes)

Rank items by days to expiry and segment into risk quartiles.

Identify request–offer matches within a chosen radius and list the nearest options.

Generate daily exchange counts by status, plus overall rollups for dashboards.

Track cumulative token balances per user over time to spot top contributors.

Detect temperature-breach clusters by household for spoilage prevention.

Quality & testing

Seeded datasets make every query demonstrable.

Constraints prevent invalid states (e.g., unknown statuses or orphaned rows).

Views provide stable entry points for dashboards and external tooling.

#Roadmap

Precise spatial indexes and native geospatial types.

Stored procedures for matching and expiry alerts.

Role-based access control and row-level security patterns.

Export of anonymized aggregates for research and policy partners.



---

## Contact

**Ali shahwaiz** — `alishahwaiz889@gmail.com`
