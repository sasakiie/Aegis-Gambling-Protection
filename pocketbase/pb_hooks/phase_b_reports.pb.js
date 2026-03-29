console.log("phase_b_reports hook loaded");

var DAILY_REPORT_LIMIT = 5;
var PROMOTION_THRESHOLD = 10;
var SELECTOR_CONSISTENCY_THRESHOLD = 0.6;
var SELECTOR_LIMIT = 20;
var SELECTOR_MAX_LENGTH = 200;
var PROMOTABLE_REPORT_TYPES = [
  "gambling_site",
  "ad_selector",
];

onRecordCreateRequest((e) => {
  try {
    const normalizeDomainLocal = (value) => {
      let domain = String(value || "").trim().toLowerCase();
      domain = domain.replace(/^https?:\/\//, "");
      domain = domain.replace(/^www\./, "");
      domain = domain.split("/")[0];
      return domain;
    };

    const normalizeSelectorsLocal = (value) => {
      const input = Array.isArray(value) ? value : [];
      const normalized = [];

      for (let i = 0; i < input.length; i += 1) {
        const selector = String(input[i] || "").trim();
        if (!selector) {
          continue;
        }
        normalized.push(selector);
      }

      normalized.sort();
      return normalized;
    };

    const validateReportPayloadLocal = (domain, selectors, reportType, reason) => {
      if (!domain || !/^[a-z0-9.-]+$/.test(domain)) {
        throw new BadRequestError("Invalid domain.");
      }

      if (![
        "gambling_site",
        "ad_selector",
        "false_positive",
        "selector_miss",
      ].includes(reportType)) {
        throw new BadRequestError("Invalid report type.");
      }

      if (reason.length > 500) {
        throw new BadRequestError("Reason is too long.");
      }

      if (!Array.isArray(selectors)) {
        throw new BadRequestError("Selectors must be an array.");
      }

      if (selectors.length > SELECTOR_LIMIT) {
        throw new BadRequestError("Too many selectors.");
      }

      for (let i = 0; i < selectors.length; i += 1) {
        if (!selectors[i] || selectors[i].length > SELECTOR_MAX_LENGTH) {
          throw new BadRequestError("Invalid selector payload.");
        }
      }
    };

    const enforceDailyQuotaLocal = (authId) => {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);

      const records = $app.findRecordsByFilter(
        "reports",
        "created_by_token = {:token} && created >= {:start}",
        "-created",
        DAILY_REPORT_LIMIT + 1,
        0,
        {
          token: authId,
          start: startOfDay.toISOString(),
        },
      );

      if (records.length >= DAILY_REPORT_LIMIT) {
        throw new ApiError(429, "Rate limit exceeded.");
      }
    };

    if (e.collection && e.collection.name !== "reports") {
      return e.next();
    }

    const authId = e.auth ? e.auth.id : "";
    if (!authId) {
      throw new BadRequestError("Anonymous auth is required.");
    }

    const domain = normalizeDomainLocal(e.record.get("domain"));
    const selectors = normalizeSelectorsLocal(e.record.get("selectors"));
    const reportType = String(e.record.get("report_type") || "");
    const reason = String(e.record.get("reason") || "").trim();

    console.log(
      "[phase_b_reports] create request",
      JSON.stringify({
        authId,
        domain,
        selectorsCount: selectors.length,
        reportType,
        reasonLength: reason.length,
      }),
    );

    validateReportPayloadLocal(domain, selectors, reportType, reason);
    enforceDailyQuotaLocal(authId);

    e.record.set("domain", domain);
    e.record.set("selectors", selectors);
    e.record.set("created_by_token", authId);
    e.record.set("status", "accepted");

    return e.next();
  } catch (error) {
    console.error("[phase_b_reports] create request failed", String(error));
    throw error;
  }
}, "reports");

onRecordAfterCreateSuccess((e) => {
  try {
    const normalizeSelectorsLocal = (value) => {
      const input = Array.isArray(value) ? value : [];
      const normalized = [];

      for (let i = 0; i < input.length; i += 1) {
        const selector = String(input[i] || "").trim();
        if (!selector) {
          continue;
        }
        normalized.push(selector);
      }

      normalized.sort();
      return normalized;
    };

    const isNotFoundErrorLocal = (error) => {
      const message = String(error || "").toLowerCase();
      return message.includes("no rows") || message.includes("not found");
    };

    const shouldCountForPromotionLocal = (reportType) =>
      PROMOTABLE_REPORT_TYPES.includes(reportType);

    const buildSelectorGroupsLocal = (reports) => {
      const groups = {};

      for (let i = 0; i < reports.length; i += 1) {
        const selectors = normalizeSelectorsLocal(reports[i].get("selectors"));
        if (selectors.length === 0) {
          continue;
        }

        const key = JSON.stringify(selectors);
        if (!groups[key]) {
          groups[key] = {
            selectors,
            count: 0,
          };
        }

        groups[key].count += 1;
      }

      return Object.values(groups).sort((a, b) => b.count - a.count);
    };

    const aggregateDomainReportsLocal = (domain) => {
      if (!domain) {
        return;
      }

      console.log("[phase_b_reports] aggregate start", domain);

      const candidateReports = $app.findRecordsByFilter(
        "reports",
        "domain = {:domain} && status != 'rejected'",
        "-created",
        200,
        0,
        { domain },
      );

      const reports = candidateReports.filter((report) =>
        shouldCountForPromotionLocal(String(report.get("report_type") || "")),
      );

      const reportCount = reports.length;
      if (reportCount < PROMOTION_THRESHOLD) {
        return;
      }

      const gamblingVotes = reports.filter((report) => !!report.get("is_gambling")).length;
      const selectorGroups = buildSelectorGroupsLocal(reports);
      const dominantSelector = selectorGroups.length > 0 ? selectorGroups[0] : null;
      const dominantSupport = dominantSelector
        ? dominantSelector.count / reportCount
        : 0;

      const canPromoteSelectors =
        dominantSelector !== null &&
        dominantSupport >= SELECTOR_CONSISTENCY_THRESHOLD;

      const canPromoteGamblingOnly =
        dominantSelector === null &&
        gamblingVotes >= PROMOTION_THRESHOLD;

      if (!canPromoteSelectors && !canPromoteGamblingOnly) {
        console.log(
          "[phase_b_reports] aggregate skipped",
          JSON.stringify({
            domain,
            reportCount,
            gamblingVotes,
            dominantSupport,
          }),
        );
        return;
      }

      const selectors = dominantSelector ? dominantSelector.selectors : [];
      const isGambling = gamblingVotes >= Math.ceil(reportCount / 2);
      const latestReport = reports[0];
      const token = String(latestReport.get("created_by_token") || "");
      const nowIso = new Date().toISOString();

      let rule = null;

      try {
        rule = $app.findFirstRecordByFilter(
          "ad_rules",
          "domain = {:domain}",
          { domain },
        );
      } catch (error) {
        if (!isNotFoundErrorLocal(error)) {
          throw error;
        }
      }

      if (!rule) {
        rule = new Record($app.findCollectionByNameOrId("ad_rules"));
        rule.set("domain", domain);
        rule.set("verified", false);
        rule.set("source_type", "report_promoted");
      }

      rule.set("selectors", selectors);
      rule.set("is_gambling", isGambling);
      rule.set("report_count", reportCount);
      rule.set("created_by_token", token);
      rule.set("last_reported_at", nowIso);

      $app.save(rule);

      for (let i = 0; i < reports.length; i += 1) {
        reports[i].set("status", "promoted");
        $app.save(reports[i]);
      }

      console.log(
        "[phase_b_reports] aggregate promoted",
        JSON.stringify({
          domain,
          reportCount,
          selectorsCount: selectors.length,
          isGambling,
        }),
      );
    };

    if (!e.record) {
      return e.next();
    }

    const domain = String(e.record.get("domain") || "");
    console.log("[phase_b_reports] after create success", domain);
    aggregateDomainReportsLocal(domain);
    return e.next();
  } catch (error) {
    console.error("[phase_b_reports] after create failed", String(error));
    throw error;
  }
}, "reports");
