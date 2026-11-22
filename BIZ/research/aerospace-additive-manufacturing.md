# Aerospace and spacecraft additive manufacturing

- **Status:** exploratory research frame
- **Owner:** BIZ
- **Date opened:** 2026-11-22
- **Maturity:** concept research only; no approved mission, customer, budget, design baseline, manufacturing route or flight programme

## Purpose

Explore whether a credible, commercially sustainable programme can design and manufacture useful spacecraft components through qualified additive-manufacturing processes.

The ambition is a traceable path from mission need and digital engineering to printed prototypes, verified ground-test articles and, only where independently accepted, flight hardware. 3D printing is a manufacturing process, not proof of strength, reliability, space suitability or qualification.

This file is a programme-research brief. It does not specify a spacecraft, propulsion system, flight part, manufacturing recipe or mission architecture. It makes no claim that a component is flight-ready.

## Ownership

- **BIZ owns the aerospace programme:** mission and customer requirements, system architecture, trade studies, budgets, technical decisions, supplier and facility relationships, safety cases, qualification strategy, funding and commercialization.
- **STUDIO owns reusable creative and fabrication tools:** general CAD, Blender, mesh inspection, rendering, export and slicer adapters. STUDIO does not own aerospace requirements or approve aerospace parts.
- **MASTER supplies cross-project methods:** research provenance, specialist routing, evidence review, risk tracking, verification contracts and change control.

A spacecraft-related request must route to BIZ even when the work uses a generic STUDIO modeling or print-preparation tool.

## Programme questions

1. **Mission and customer:** What civil, scientific, commercial or infrastructure need is being served? Who operates and pays for the system, and what existing alternatives are better or cheaper?
2. **System context:** What environment, orbit or trajectory, lifetime, launch interface, reliability, power, thermal, data, communications and regulatory constraints actually apply?
3. **Part suitability:** Which candidate components benefit from additive manufacturing over conventional manufacture? What are the interfaces, failure consequences, inspection access and repair/replacement assumptions?
4. **Process capability:** Which material, feedstock, machine, facility, build process and post-processing route can be controlled and evidenced for the specific part?
5. **Qualification:** What analysis, inspection, destructive and non-destructive tests, environmental tests and independent reviews are needed before each maturity claim?
6. **Business case:** What equipment, facility, specialist labour, test access, insurance, certification, supply-chain and schedule costs determine viability?

Do not assume additive manufacturing is lighter, cheaper, stronger or faster. Compare it against machined, formed, cast, composite and qualified off-the-shelf alternatives using the same requirements and lifecycle assumptions.

## Evidence and manufacturing controls

Every candidate part needs a controlled identity and revision, requirement traceability, material and feedstock provenance, machine and facility identity, operator competence, calibrated equipment, approved process parameters, build records, post-processing history, inspection results, non-conformance disposition and configuration history.

A qualification argument must consider, as applicable to the actual part and environment:

- material pedigree, contamination, powder or feedstock handling and reuse;
- process repeatability, build orientation, anisotropy, porosity, residual stress and defects;
- heat treatment, machining, surface condition, dimensional inspection and interface fit;
- NDE method capability, acceptance criteria, witness samples and lot traceability;
- loads, fatigue, fracture, vibration, shock, thermal cycling, thermal vacuum, outgassing, radiation and corrosion;
- software, data, file and process configuration control, including cybersecurity and supplier access.

A coupon, material datasheet, successful print, finite-element result or single environmental test is only one evidence item. It does not qualify the complete part or system. Qualification belongs to the responsible engineering authority and requires independent review against the actual requirements and contractual standards.

## Stage gates

| Gate | Decision | Minimum evidence |
|---|---|---|
| G0 — Need and scope | Is there a real mission need and lawful, fundable customer problem? | Customer evidence, mission context, jurisdiction/export-control screening, alternatives and explicit unknowns |
| G1 — Feasibility | Is additive manufacturing justified for a defined candidate part? | Requirements, interface definition, trade study, material/process shortlist, preliminary hazard and cost assessment |
| G2 — Prototype | Can the selected route produce repeatable ground-test articles? | Controlled source model, build record, material pedigree, dimensional inspection, non-conformance log and test plan |
| G3 — Qualification | Does the part meet its allocated requirements under the applicable verification programme? | Approved qualification matrix, process qualification, analysis, inspection, test reports, independent review and closure of deviations |
| G4 — Flight acceptance | Has the responsible programme authority accepted the exact configuration for the intended mission? | Configuration baseline, full traceability, approved verification closure, safety and mission acceptance records |

A gate may return to an earlier stage or stop the work. No marketing deadline, grant application or successful prototype may waive an engineering gate.

## Standards research register

The following are primary-source research leads, not a declaration that NASA requirements govern this programme. Applicability, contractual flow-down, jurisdiction, revision and tailoring must be confirmed for each customer and mission.

| Reference | Current source observation | Use in research |
|---|---|---|
| [NASA-STD-6030](https://standards.nasa.gov/node/2739) | NASA lists it as active; its scope addresses additive-manufacturing processes used in design, fabrication and testing of spaceflight hardware. | Study the system-level AM requirements and how a customer tailors them |
| [NASA-STD-6033](https://standards.nasa.gov/node/2740) | NASA lists it as active and records revalidation on 2026-01-07; it concerns equipment and facility control. | Study machine, facility, operator, feedstock and process-control expectations |
| [NASA-HDBK-5026](https://standards.nasa.gov/all-standards) | NASA's standards catalogue lists guidance on strength, fatigue and fracture control for additively manufactured spaceflight hardware. | Review structural substantiation and failure-control guidance |
| [ISO/ASTM 52900:2021](https://www.iso.org/standard/74514.html) | ISO says the second edition was reviewed and confirmed in 2025 and remains current. | Use as general AM terminology and fundamentals, not spacecraft qualification |

NASA standards are NASA standards, not universal certification. Identify applicable ECSS, ISO, ASTM, national, launch-provider and customer requirements in a separate revision-controlled matrix before design work is treated as a programme baseline.

## Commercial work

The commercial case must distinguish actual customer commitments from interviews, letters of interest, forecasts and grant hypotheses. Build a supplier and facility map only from verified capabilities. Model non-recurring engineering, machine time, feedstock, post-processing, inspection, qualification, rework, failed builds, logistics, insurance and programme overhead.

Potential business models—contract manufacturing, design-for-additive engineering, qualified process development, component supply or partnerships—must be compared against customer demand, capital requirements, liability and realistic utilisation. Do not present grants, partners, machines, customers or revenue as secured unless documentary evidence supports the statement.

## Immediate research tasks

1. Define a civil mission/customer problem before selecting a spacecraft concept.
2. Build a traceable requirements and regulatory-jurisdiction register.
3. Identify candidate component classes and compare additive with conventional manufacture.
4. Map qualified material, machine, post-processing and test capabilities from primary supplier evidence.
5. Build a risk register covering engineering, manufacturing, supply chain, safety, export controls, liability, funding and schedule.
6. Draft a gate-based cost and verification plan with explicit assumptions and stop conditions.
7. Commission independent aerospace and materials/process review before any detailed flight-hardware design is adopted.

**Release rule:** this research note may support discovery and funding discussions only when its status and uncertainty are visible. It must not be used to imply a spacecraft has been designed, built, tested, qualified or accepted for flight.
