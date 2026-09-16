import fs from 'node:fs/promises';
import { SpreadsheetFile, Workbook } from '@oai/artifact-tool';

const outDir = '/Users/vipulswarup/coding/alfresco-work/alfresco-26/alfresco-ubuntu-installer';
const wb = Workbook.create();
const summary = wb.worksheets.add('Summary');
const tests = wb.worksheets.add('UAT Test Cases');
summary.showGridLines = false;
tests.showGridLines = false;
summary.tabColor = '#1F4E78';
tests.tabColor = '#70AD47';

const cases = [
  ['WF-01','JKLC workflow','Folder configuration','Create/configure a target folder with the required scwf:userSelect configuration; save; reopen the folder settings.','Folder configuration saves successfully and is retained after refresh/relogin.','High'],
  ['WF-02','JKLC workflow','Automatic upload trigger','Configure a folder for automatic upload workflow; upload a disposable document; wait for workflow creation.','Exactly one JKLC workflow instance is created for the uploaded document and the expected reviewer task is assigned.','High'],
  ['WF-03','JKLC workflow','Sequential approval','Start a sequential review with disposable users; reviewer 1 approves; reviewer 2 approves; complete initiator acknowledgement.','Tasks progress in sequence, notifications are sent, and the workflow completes with the document in the expected state.','High'],
  ['WF-04','JKLC workflow','Sequential rejection','Start a sequential review; have a reviewer reject; complete any acknowledgement task.','Rejection transition succeeds, the initiator receives the expected notification, and no orphan active task remains.','High'],
  ['WF-05','JKLC workflow','Version-change path','Start a review; create a new document version while the workflow is active; inspect the task and history.','Version-change behavior matches the business rule and the workflow references the correct document/version.','Medium'],
  ['WF-06','JKLC workflow','Permission enforcement','Attempt workflow actions as initiator, assigned reviewer, non-assigned user, and unrelated site member.','Only authorized users can view or act on tasks; unauthorized attempts are denied without data leakage.','High'],
  ['WF-07','JKLC workflow','Email templates','Run a successful and rejected workflow; inspect all initiator/reviewer emails and links.','Correct EisenVault email templates are used, recipients are correct, links resolve, and no sensitive values leak.','Medium'],
  ['WF-08','Show All Workflows','History visibility','Open workflow history for a document as administrator, initiator, reviewer, and unrelated user.','History visibility matches the approved role policy; unauthorized users cannot view another user’s workflow details.','High'],
  ['SH-01','Share UI','Login and dashboard','Open Share through the production reverse-proxy URL; log in as admin and standard user; navigate the dashboard.','Login, logout, dashboard loading, navigation, branding, and browser console are error-free.','High'],
  ['SH-02','Share UI','Document Library','Open Document Library; browse folders; upload a disposable text file; rename, move, and delete it if permitted.','Library loads correctly and permitted content actions work without JavaScript, template, or permission errors.','High'],
  ['SH-03','Share UI','PDF preview','Upload/open a PDF and inspect the preview, thumbnail, download, and print controls.','PDF preview renders the intended rendition; controls follow the user role and no original-content bypass exists.','High'],
  ['SH-04','Share UI','Office preview regression','Upload one DOCX, XLSX, and PPTX; open each in Share preview.','Each supported Office file produces a correct preview and thumbnail with no conversion errors.','High'],
  ['SH-05','Share UI','Image/media preview','Upload representative JPG/PNG and media files; open previews and inspect metadata.','Supported images/media preview correctly; unsupported formats fail gracefully with a clear message.','Medium'],
  ['SH-06','Share UI','Search','Create a unique disposable document; search for its unique phrase; use filters and suggestions.','The document becomes searchable within the expected interval and filters/suggestions return correct results.','High'],
  ['SH-07','Share UI','SiteViewer action restrictions','Log in as SiteViewer, including a user with overlapping Consumer access; inspect document and folder actions.','Download, view-in-browser, print-as-PDF, folder-download, copy, and header download actions are hidden or denied.','Critical'],
  ['SH-08','Share UI','SiteViewer derived preview','As SiteViewer, open a permitted derived preview; try direct source URLs, rendition URLs, REST, and legacy content URLs.','Only whitelisted derived renditions are served; source content and unauthorized renditions are denied, including direct/API access.','Critical'],
  ['SH-09','Share UI','Compressed-PDF badge','Place a PDF below an ev:pdffolder ancestor and inspect the document header; repeat outside the ancestor.','The compressed-PDF label appears only when the required ancestor/aspect condition is true.','Medium'],
  ['SH-10','Share UI','Authorization negatives','Attempt to access sites, documents, actions, previews, and workflow pages using users with insufficient roles.','Every unauthorized operation is denied consistently with no content, metadata, or error-detail leakage.','High'],
  ['SH-11','Share UI','Browser/reverse proxy/CSP','Test supported browsers through the real TLS/reverse-proxy path; inspect network, CSP, and console errors.','No mixed-content, CSP, path, TLS, or browser compatibility errors block core workflows.','Medium'],
  ['OO-01','ONLYOFFICE','DOCX edit/save','Open a disposable DOCX in ONLYOFFICE; edit content; save and close; reopen in Share.','Edits save to Alfresco, the document remains readable, and the expected version is created.','High'],
  ['OO-02','ONLYOFFICE','XLSX edit/save','Repeat editing and saving with an XLSX containing formulas and formatting.','Workbook edits, formulas, and formatting persist correctly after callback and reopen.','High'],
  ['OO-03','ONLYOFFICE','PPTX edit/save','Repeat editing and saving with a PPTX containing multiple slides and images.','Presentation edits and embedded images persist correctly after callback and reopen.','Medium'],
  ['OO-04','ONLYOFFICE','Version creation','Edit the same document multiple times and inspect Alfresco version history.','Each configured save creates the expected version, with correct creator, timestamp, and content.','High'],
  ['OO-05','ONLYOFFICE','Lock/conflict behavior','Open the same document as two users; edit concurrently; save from both sessions.','Locks/conflicts are handled predictably; no silent overwrite occurs and users receive clear feedback.','High'],
  ['OO-06','ONLYOFFICE','Permissions','Try opening/editing as owner, Consumer, SiteViewer, and unauthorized user.','Only users with edit permission can edit/save; view-only and unauthorized users cannot modify content.','High'],
  ['OO-07','ONLYOFFICE','Document Server recovery','Stop or disconnect the Document Server during an edit; restore it; retry the operation.','Failure is visible, no corrupt callback is recorded, and service recovers without manual database cleanup.','High'],
  ['OO-08','ONLYOFFICE','Restart/JWT smoke test','Restart repository, Share, and Document Server; open the editor and save a disposable file.','JWT authentication remains valid after restart and the editor/callback path works end-to-end.','High'],
  ['PDF-01','PDF Toolkit','Page rotation','Open the PDF action form; rotate selected pages on a disposable PDF; download/open result.','Form loads, rotation applies only to selected pages, and the output PDF opens successfully.','Medium'],
  ['PDF-02','PDF Toolkit','Watermarking','Apply a text/image watermark using the browser form to a disposable PDF.','Watermark is applied with the requested position/opacity and the original remains unchanged.','Medium'],
  ['PDF-03','PDF Toolkit','Splitting','Split a disposable multi-page PDF by selected pages/ranges.','All expected output files are created with correct page counts and readable content.','Medium'],
  ['PDF-04','PDF Toolkit','Encryption/decryption','Encrypt a disposable PDF with a test password; reopen; decrypt it through the action form.','Encryption blocks access without the password; decryption succeeds with the correct password and preserves content.','High'],
  ['PDF-05','PDF Toolkit','E-Sign retirement','Inspect Document Library actions for several document types as admin and standard user.','No E-Sign/digital-signature action is exposed anywhere in the retained PDF Toolkit UI.','High'],
  ['REPO-01','Repository','Custom endpoint regression','Exercise custom REST/web-script endpoints for welcome, size, user count, password, audit, and workflow helpers.','Authorized calls return the documented response; invalid input and unauthorized calls are rejected safely.','High'],
  ['OCR-01','Remote OCR','OCR happy path','Upload an image/PDF requiring OCR; monitor asynchronous submission, callback, rendition metadata, and searchable text.','OCR job completes, callback is accepted once, rendition metadata is correct, and extracted text is searchable.','Critical'],
  ['OCR-02','Remote OCR','OCR retry/timeout','Simulate OCR service delay/failure; observe retries, timeout, queue state, and user-visible status.','Retries are bounded/idempotent, timeout is visible, and the document is not left in an ambiguous state.','High'],
  ['OCR-03','Remote OCR','OCR new version','OCR a document, create a new version, and repeat OCR; inspect renditions and metadata.','Each version has correct OCR processing and no rendition or callback is attached to the wrong version.','High'],
  ['TR-01','Transformations','Compressed PDF rendition','Place a PDF below ev:pdffolder; trigger the named compressedPdf rendition; inspect limits and output.','Bounded Ghostscript transformation creates a valid compressed PDF without blocking normal PDF handling.','Critical'],
  ['TR-02','Transformations','DWG/DXF preview','Upload representative DWG/DXF files covering model space, layouts, fonts, and multi-page output.','CAD T-Engine creates readable PDF previews for supported files and fails safely for unsupported files.','Critical'],
  ['DATA-01','Data migration','Model and metadata validation','Migrate a representative dataset; compare custom models, namespaces, aspects, types, constraints, permissions, and versions.','Existing content remains readable and metadata, permissions, versions, and workflow references are preserved.','Critical'],
  ['DATA-02','Data migration','Search/reindex validation','After migration, reindex Solr; check alfresco/archive cores, tracker state, and representative search results.','Indexes are healthy, tracker lag returns to normal, and search results/counts match the migrated repository.','High'],
  ['OPS-01','Operations','Backup/restore rehearsal','Take verified database/content/Solr/config backups; restore to a disposable environment; run smoke tests.','Restore completes, services start in the correct order, content/search work, and rollback evidence is recorded.','Critical'],
  ['OPS-02','Operations','Cutover and hypercare','Execute the timed production cutover runbook including go/no-go, rollback decision points, and monitoring.','Cutover completes within target time, rollback is actionable, and monitoring covers logs, Solr, OCR, disk, JVM, and database health.','Critical'],
];

const headers = ['Test ID','Area','Test case','Steps to reproduce','Expected result','Priority','Actual result','Status','Defect / notes','Tester','Test date'];
tests.getRange('A1:K1').merge();
tests.getRange('A1').values = [['ACS 26.1 Migration — Manual UAT Test Plan']];
tests.getRange('A2:K2').merge();
tests.getRange('A2').values = [['Instructions: execute each test manually, record Actual result and Defect / notes, then set Status to Pass, Fail, Blocked, or Not Run. Use disposable test users/documents unless the case explicitly targets migrated data.']];
tests.getRange('A4:K4').values = [headers];
tests.getRange(`A5:F${cases.length+4}`).values = cases;
tests.getRange(`G5:K${cases.length+4}`).values = cases.map(() => ['', 'Not Run', '', '', '']);
tests.getRange(`A4:K${cases.length+4}`).format.wrapText = true;
tests.getRange('A1:K1').format = { fill: '#1F4E78', font: { color: '#FFFFFF', bold: true, size: 16 }, horizontalAlignment: 'center', verticalAlignment: 'center' };
tests.getRange('A2:K2').format = { fill: '#D9EAF7', font: { color: '#1F1F1F', italic: true }, wrapText: true, verticalAlignment: 'center' };
tests.getRange('A4:K4').format = { fill: '#5B9BD5', font: { color: '#FFFFFF', bold: true }, horizontalAlignment: 'center', verticalAlignment: 'center', wrapText: true };
tests.getRange(`A5:A${cases.length+4}`).format.font = { bold: true, color: '#1F4E78' };
tests.getRange(`F5:F${cases.length+4}`).format.horizontalAlignment = 'center';
tests.getRange(`H5:H${cases.length+4}`).format = { fill: '#FFF2CC', horizontalAlignment: 'center', font: { bold: true } };
tests.getRange('A1:K1').format.rowHeight = 28;
tests.getRange('A2:K2').format.rowHeight = 40;
tests.getRange('A4:K4').format.rowHeight = 34;
tests.getRange(`A5:K${cases.length+4}`).format.rowHeight = 72;
for (const [col, width] of [['A',11],['B',18],['C',26],['D',62],['E',58],['F',11],['G',42],['H',13],['I',42],['J',18],['K',14]]) tests.getRange(`${col}:${col}`).format.columnWidth = width;
tests.freezePanes.freezeRows(4);

summary.getRange('A1:H1').merge();
summary.getRange('A1').values = [['ACS 26.1 Migration — UAT Execution Summary']];
summary.getRange('A3:B9').values = [
  ['Metric','Value'],
  ['Total test cases', null],
  ['Not Run', null],
  ['Pass', null],
  ['Fail', null],
  ['Blocked', null],
  ['Completion %', null],
];
summary.getRange('B4:B8').formulas = [[`=COUNTA('UAT Test Cases'!A5:A${cases.length+4})`],[`=COUNTIF('UAT Test Cases'!H5:H${cases.length+4},"Not Run")`],[`=COUNTIF('UAT Test Cases'!H5:H${cases.length+4},"Pass")`],[`=COUNTIF('UAT Test Cases'!H5:H${cases.length+4},"Fail")`],[`=COUNTIF('UAT Test Cases'!H5:H${cases.length+4},"Blocked")`]];
summary.getRange('B9').formulas = [['=IF(B4=0,0,(B6+B7+B8)/B4)']];
summary.getRange('A12:H12').merge();
summary.getRange('A12').values = [['Execution guidance']];
summary.getRange('A13:H17').merge();
summary.getRange('A13').values = [['Start with Critical and High priority cases. Record exact URLs, usernames/roles, document names, timestamps, HTTP status codes, screenshots, and relevant log excerpts for failures. Do not place passwords, private keys, or other secrets in this workbook.']];
summary.getRange('A20:B20').values = [['Priority','Count']];
summary.getRange('A21:A23').values = [['Critical'],['High'],['Medium']];
summary.getRange('B21:B23').formulas = [[`=COUNTIF('UAT Test Cases'!F5:F${cases.length+4},A21)`],[`=COUNTIF('UAT Test Cases'!F5:F${cases.length+4},A22)`],[`=COUNTIF('UAT Test Cases'!F5:F${cases.length+4},A23)`]];
summary.getRange('A1:H1').format = { fill: '#1F4E78', font: { color: '#FFFFFF', bold: true, size: 16 }, horizontalAlignment: 'center', verticalAlignment: 'center' };
summary.getRange('A3:B3').format = { fill: '#5B9BD5', font: { color: '#FFFFFF', bold: true }, horizontalAlignment: 'center' };
summary.getRange('A12:H12').format = { fill: '#70AD47', font: { color: '#FFFFFF', bold: true } };
summary.getRange('A13:H17').format = { fill: '#E2F0D9', wrapText: true, verticalAlignment: 'center' };
summary.getRange('A20:B20').format = { fill: '#5B9BD5', font: { color: '#FFFFFF', bold: true } };
summary.getRange('B9').format.numberFormat = '0%';
summary.getRange('A1:H1').format.rowHeight = 28;
summary.getRange('A13:H17').format.rowHeight = 24;
summary.getRange('A:A').format.columnWidth = 24;
summary.getRange('B:B').format.columnWidth = 18;
summary.getRange('C:H').format.columnWidth = 14;
summary.freezePanes.freezeRows(3);

await wb.recalculate();
const check = await wb.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!', options: { useRegex: true, maxResults: 50 }, summary: 'formula error scan' });
console.log(check.ndjson);
for (const [sheetName, range] of [['Summary','A1:H23'],['UAT Test Cases','A1:K12']]) {
  const preview = await wb.render({ sheetName, range, scale: 1, format: 'png' });
  await fs.writeFile(`${outDir}/${sheetName.replaceAll(' ','_')}_preview.png`, new Uint8Array(await preview.arrayBuffer()));
}
const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(`${outDir}/acs26_migration_uat_test_plan.xlsx`);
console.log('created acs26_migration_uat_test_plan.xlsx');
