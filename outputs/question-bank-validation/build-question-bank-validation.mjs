import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputRoot = path.resolve(process.argv[2] ?? ".");
const packageDir = path.join(outputRoot, "2019国考地市级真题验证包");
const assetsDir = path.join(packageDir, "assets");
const referenceAssets = path.join(outputRoot, "核对样稿", "assets");
const xlsxPath = path.join(packageDir, "真题导入验证.xlsx");
const previewDir = path.join(outputRoot, "previews");

const paperID = "gk-2019-city";
const materialID = "m-2019-drugs-111-115";
const moduleIDs = [1, 2, 3, 4, 5].map((n) => `${paperID}-module-${n}`);
const sheets = {
  guide: "导入说明",
  paper: "试卷",
  modules: "模块",
  materials: "材料",
  questions: "题目",
  assets: "图片资源",
};

const modules = [
  [moduleIDs[0], paperID, 1, "一、常识判断", "根据题目要求，在四个选项中选出一个最恰当的答案。", "2"],
  [moduleIDs[1], paperID, 2, "二、言语理解与表达", "本部分包括表达与理解两方面的内容。请根据题目要求，在四个选项中选出一个最恰当的答案。", "5"],
  [moduleIDs[2], paperID, 3, "三、数量关系", "在这部分试题中，每道题呈现一段表述数字关系的文字，要求你迅速、准确地计算出答案。", "14"],
  [moduleIDs[3], paperID, 4, "四、判断推理", "本部分包括图形推理、定义判断、类比推理与逻辑判断四种类型的试题。", "16"],
  [moduleIDs[4], paperID, 5, "五、资料分析", "所给出的图、表、文字或综合性资料均有若干个问题要你回答。你应根据资料提供的信息进行分析、比较、计算和判断处理。", "25-26"],
];

const questionData = [
  {
    id: "q-2019-001", number: 1, moduleID: moduleIDs[0], subject: "常识判断", type: "纯文字", materialID: "",
    stem: "党的十八大以来，以习近平同志为核心的党中央，紧密结合新的时代条件和实践要求，以全新的视野深化对共产党执政规律、社会主义建设规律、人类社会发展规律的认识，创立了习近平新时代中国特色社会主义思想，其核心要义是：",
    stemAsset: "", options: ["坚持和发展中国特色社会主义", "中国特色社会主义进入了新时代", "实现社会主义现代化和中华民族伟大复兴", "坚持以人民为中心的发展思想"],
    optionAssets: ["", "", "", ""], answer: "A", page: "2",
  },
  {
    id: "q-2019-071", number: 71, moduleID: moduleIDs[3], subject: "判断推理", type: "图形推理", materialID: "",
    stem: "从所给的四个选项中，选择最合适的一个填入问号处，使之呈现一定的规律性：",
    stemAsset: "q-2019-071-full-figure", options: ["A", "B", "C", "D"],
    optionAssets: ["", "", "", ""], answer: "B", page: "16",
  },
  {
    id: "q-2019-111", number: 111, moduleID: moduleIDs[4], subject: "资料分析", type: "图表资料", materialID,
    stem: "2017年第三季度，全国平均每吨进口药品单价约为多少万美元？", stemAsset: "",
    options: ["2", "19", "8", "96"], optionAssets: ["", "", "", ""], answer: "B", page: "25",
  },
  {
    id: "q-2019-112", number: 112, moduleID: moduleIDs[4], subject: "资料分析", type: "图表资料", materialID,
    stem: "2017年下半年，全国进口药品数量同比增速低于上月水平的月份有几个？", stemAsset: "",
    options: ["2", "3", "4", "5"], optionAssets: ["", "", "", ""], answer: "C", page: "25",
  },
  {
    id: "q-2019-113", number: 113, moduleID: moduleIDs[4], subject: "资料分析", type: "图表资料", materialID,
    stem: "2016年5月，全国进口药品金额环比增速：", stemAsset: "",
    options: ["超过100%", "在40%～100%之间", "在0%～40%之间", "低于0%"], optionAssets: ["", "", "", ""], answer: "C", page: "25",
  },
  {
    id: "q-2019-114", number: 114, moduleID: moduleIDs[4], subject: "资料分析", type: "图片型选项", materialID,
    stem: "以下折线图中，能准确反映2017年第四季度各月全国进口药品金额环比增长率的是：", stemAsset: "",
    options: ["A", "B", "C", "D"],
    optionAssets: ["q-2019-114-option-a", "q-2019-114-option-b", "q-2019-114-option-c", "q-2019-114-option-d"], answer: "D", page: "26",
  },
  {
    id: "q-2019-115", number: 115, moduleID: moduleIDs[4], subject: "资料分析", type: "图表资料", materialID,
    stem: "能够从上述资料中推出的是：", stemAsset: "",
    options: [
      "2016年下半年，全国进口药品数量低于1万吨的月份仅有2个",
      "2017年11月，全国平均每吨进口药品单价低于上年同期水平",
      "2017年第二季度，全国进口药品金额超过75亿美元",
      "2017年1月，全国进口药品金额超过20亿美元",
    ], optionAssets: ["", "", "", ""], answer: "B", page: "26",
  },
];

const assetData = [
  { id: "q-2019-071-full-figure", ownerType: "question", ownerID: "q-2019-071", role: "题干整图", source: "q071-combined-figure.png", path: "assets/q071-combined-figure.png", page: "16" },
  { id: "m-2019-drugs-111-115-chart", ownerType: "material", ownerID: materialID, role: "共用材料", source: "shared-material-111-115.png", path: "assets/shared-material-111-115.png", page: "25" },
  ...["a", "b", "c", "d"].map((letter) => ({
    id: `q-2019-114-option-${letter}`, ownerType: "option", ownerID: "q-2019-114", role: `选项${letter.toUpperCase()}`,
    source: `q114-option-${letter}-graph.png`, path: `assets/q114-option-${letter}-graph.png`, page: "26",
  })),
];

const headersStyle = {
  fill: "#1D4ED8", font: { name: "Arial", size: 10, bold: true, color: "#FFFFFF" },
  horizontalAlignment: "center", verticalAlignment: "center", wrapText: true,
  borders: { preset: "all", style: "thin", color: "#BFDBFE" },
};

function columnName(index) {
  let value = index;
  let result = "";
  while (value > 0) {
    const remainder = (value - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    value = Math.floor((value - 1) / 26);
  }
  return result;
}

function prepareSheet(sheet, title, subtitle) {
  sheet.showGridLines = false;
  sheet.getRange("A1").values = [[title]];
  sheet.getRange("A1").format.font = { name: "Arial", size: 16, bold: true, color: "#172554" };
  sheet.getRange("A2").values = [[subtitle]];
  sheet.getRange("A2").format = { font: { name: "Arial", size: 10, italic: true, color: "#64748B" }, wrapText: false };
}

function writeTable(sheet, headers, rows, name) {
  const lastColumn = columnName(headers.length);
  const lastRow = 4 + rows.length;
  sheet.getRange(`A4:${lastColumn}${lastRow}`).values = [headers, ...rows];
  sheet.getRange(`A4:${lastColumn}4`).format = headersStyle;
  if (rows.length) sheet.getRange(`A5:${lastColumn}${lastRow}`).format = {
    font: { name: "Arial", size: 10, color: "#1F2937" }, verticalAlignment: "top", wrapText: true,
    borders: { preset: "insideHorizontal", style: "thin", color: "#E2E8F0" },
  };
  sheet.tables.add(`A4:${lastColumn}${lastRow}`, true, name);
  sheet.freezePanes.freezeRows(4);
}

async function main() {
  await fs.mkdir(packageDir, { recursive: true });
  await fs.mkdir(assetsDir, { recursive: true });
  await fs.mkdir(previewDir, { recursive: true });

  // Remove only the known obsolete files from the previous, incorrect q071 schema.
  const obsolete = ["q071-stem.png", "q071-option-a.png", "q071-option-b.png", "q071-option-c.png", "q071-option-d.png",
    "m2019-drugs-charts.png", "q114-option-a.png", "q114-option-b.png", "q114-option-c.png", "q114-option-d.png"];
  await Promise.all(obsolete.map((name) => fs.rm(path.join(assetsDir, name), { force: true })));
  for (const asset of assetData) await fs.copyFile(path.join(referenceAssets, asset.source), path.join(packageDir, asset.path));

  const workbook = Workbook.create();
  const guide = workbook.worksheets.add(sheets.guide);
  const paper = workbook.worksheets.add(sheets.paper);
  const moduleSheet = workbook.worksheets.add(sheets.modules);
  const materialSheet = workbook.worksheets.add(sheets.materials);
  const questionSheet = workbook.worksheets.add(sheets.questions);
  const assetSheet = workbook.worksheets.add(sheets.assets);

  prepareSheet(guide, "真题导入验证包", "2019年国考地市级行测：纯文字、图形推理、资料分析共用材料与图片选项样本。此包仅验证导入与查看，不含作答/计时/成绩功能。");
  const guideRows = [
    ["导入单位", "一个 ZIP：根目录唯一 .xlsx 工作簿 + assets/ 图片目录。选择 ZIP 后先校验和预览，再由用户确认。"],
    ["试卷表", "一个导入包且仅一套试卷；试卷ID是稳定身份。重复导入按试卷ID或年份、考试类型、卷别、名称识别，并提示替换或取消。"],
    ["模块表", "一至五模块标题和说明单独保存；模块ID、试卷ID及序号稳定，不属于题干或材料。"],
    ["材料表", "共用材料只保存一份，通过材料ID被题目引用。模块标题/说明不得放入材料。"],
    ["题目表", "题干、A-D选项和答案分列；图片通过图片资源ID关联。解析列留空，不由应用生成解析。"],
    ["图片资源表", "图片位于 ZIP 根目录 assets/，表格记录稳定图片ID、所属记录、用途和相对路径；禁止 Base64。"],
    ["完整性规则", "题号、记录ID和图片ID不可重复；答案只能是A-D；所有模块、材料、题目、图片关联必须存在。"],
    ["图片规则", "Q71使用一张包含题干图形和A-D图形选项的完整图；Q114使用四张只有折线、不带题干和字母的选项图。"],
    ["资料分析规则", "Q111-Q115分别保存题干并引用同一材料ID；“五、资料分析”及作答说明只在模块表。"],
    ["本包范围", "已核对样题仅包含Q1、Q71、Q111-Q115；五个模块结构完整，不代表其余题目已导入。"],
  ];
  guide.getRange(`A4:B${guideRows.length + 3}`).values = guideRows;
  guide.getRange(`A4:A${guideRows.length + 3}`).format = {
    fill: "#EFF6FF", font: { name: "Arial", size: 10, bold: true, color: "#1D4ED8" }, verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: "#BFDBFE" },
  };
  guide.getRange(`B4:B${guideRows.length + 3}`).format = {
    font: { name: "Arial", size: 10, color: "#1F2937" }, wrapText: true, verticalAlignment: "center",
    borders: { preset: "outside", style: "thin", color: "#BFDBFE" },
  };
  guide.getRange(`A4:B${guideRows.length + 3}`).format.rowHeight = 38;
  guide.getRange("A:A").format.columnWidth = 20;
  guide.getRange("B:B").format.columnWidth = 96;

  prepareSheet(paper, "试卷", "一套导入包只包含一套试卷。稳定试卷ID用于重复检测。");
  writeTable(paper, ["试卷ID", "试卷名称", "年份", "考试类型", "卷别", "来源", "导入版本"], [[
    paperID, "2019年国家公务员录用考试《行测》题（地市级网友回忆版）", 2019, "国考", "地市级", "用户提供的带答案 PDF", "1.1",
  ]], "PapersTable");
  [22, 56, 10, 14, 14, 28, 12].forEach((width, index) => { paper.getRange(`${columnName(index + 1)}:${columnName(index + 1)}`).format.columnWidth = width; });
  paper.getRange("A5:G5").format.rowHeight = 44;

  prepareSheet(moduleSheet, "模块", "整卷结构：标题和作答说明各占独立字段，不混入题干或共用材料。");
  writeTable(moduleSheet, ["模块ID", "试卷ID", "模块序号", "模块标题", "模块说明", "原始页码"], modules, "ModulesTable");
  [26, 22, 12, 28, 104, 12].forEach((width, index) => { const col = columnName(index + 1); moduleSheet.getRange(`${col}:${col}`).format.columnWidth = width; });
  moduleSheet.getRange("A5:F9").format.rowHeight = 54;

  prepareSheet(materialSheet, "材料", "第111-115题共同引用一次的图表材料；不含“五、资料分析”模块标题。");
  writeTable(materialSheet, ["材料ID", "试卷ID", "模块ID", "材料类型", "材料文字", "材料图片资源ID", "适用题号", "原始页码"], [[
    materialID, paperID, moduleIDs[4], "图表", "", "m-2019-drugs-111-115-chart", "111-115", "25",
  ]], "MaterialsTable");
  [28, 22, 26, 14, 58, 36, 16, 12].forEach((width, index) => { const col = columnName(index + 1); materialSheet.getRange(`${col}:${col}`).format.columnWidth = width; });
  materialSheet.getRange("A5:H5").format.rowHeight = 52;

  prepareSheet(questionSheet, "题目", "题号在本卷唯一；题干图片与选项图片分开关联。Q71选项字段为A/B/C/D；Q114图片选项也保留独立字母字段。");
  const questionHeaders = [
    "题目ID", "试卷ID", "模块ID", "题号", "科目", "题型", "材料ID", "题干", "题干图片资源ID",
    "选项A", "选项A图片资源ID", "选项B", "选项B图片资源ID", "选项C", "选项C图片资源ID", "选项D", "选项D图片资源ID",
    "正确答案", "解析", "原始页码",
  ];
  const questionRows = questionData.map((question) => [
    question.id, paperID, question.moduleID, question.number, question.subject, question.type, question.materialID,
    question.stem, question.stemAsset, question.options[0], question.optionAssets[0], question.options[1], question.optionAssets[1],
    question.options[2], question.optionAssets[2], question.options[3], question.optionAssets[3], question.answer, "", question.page,
  ]);
  writeTable(questionSheet, questionHeaders, questionRows, "QuestionsTable");
  [20, 22, 26, 8, 14, 20, 28, 86, 32, 34, 32, 34, 32, 34, 32, 34, 32, 12, 30, 12]
    .forEach((width, index) => { const col = columnName(index + 1); questionSheet.getRange(`${col}:${col}`).format.columnWidth = width; });
  questionSheet.getRange(`A5:T${4 + questionRows.length}`).format.rowHeight = 66;

  prepareSheet(assetSheet, "图片资源", "ZIP 内图片文件的相对路径从包根目录计算。所有图片均作为独立文件保存，不写入表格单元格。");
  const assetRows = assetData.map((asset) => [asset.id, paperID, asset.ownerType, asset.ownerID, asset.role, asset.path,
    "image/png", path.basename(asset.path), asset.page]);
  writeTable(assetSheet, ["图片资源ID", "试卷ID", "所属类型", "所属ID", "用途", "相对路径", "MIME类型", "文件名", "原始页码"], assetRows, "AssetsTable");
  [38, 22, 15, 30, 16, 48, 14, 36, 12].forEach((width, index) => { const col = columnName(index + 1); assetSheet.getRange(`${col}:${col}`).format.columnWidth = width; });
  assetSheet.getRange(`A5:I${4 + assetRows.length}`).format.rowHeight = 32;

  workbook.recalculate();
  for (const sheetName of Object.values(sheets)) {
    const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1.2, format: "png" });
    await fs.writeFile(path.join(previewDir, `${sheetName}.png`), new Uint8Array(await preview.arrayBuffer()));
  }
  const xlsx = await SpreadsheetFile.exportXlsx(workbook);
  await xlsx.save(xlsxPath);
  // The artifact SDK's inspection sidecar is useful during authoring, but the
  // import ZIP contract permits only the workbook and declared image resources.
  await fs.rm(`${xlsxPath}.inspect.ndjson`, { force: true });
  console.log(`Created ${xlsxPath}`);
  console.log(`Validated sample rows: ${questionData.length} questions, ${modules.length} modules, ${assetData.length} image assets`);
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
