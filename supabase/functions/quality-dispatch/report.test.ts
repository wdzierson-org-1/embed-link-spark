import { expect, it } from 'vitest';
import { reportText } from './report';
it('reports recorded asset structure checks without claiming visual accuracy', () => {
  const text = reportText({ report_day:'2026-10-10',job_count:1,completed:1,failed:0,pending:0,results:[{retrieval:{outcome:'retrieved',item_id:'id',url:'https://example.org',captured_at:'2026-10-10',image_checks:[{outcome:'usable_asset',reason:'raster_structure_valid',duration_ms:120,width:640,height:480,byte_length:20000}]}}] });
  expect(text).toContain('usable_asset (raster_structure_valid; 120 ms); 640 × 480; 20000 bytes');
  expect(text).toContain('visual match and full decoding are unverified');
  expect(text).toContain('09:00 America/New_York');
});
