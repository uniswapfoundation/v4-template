#!/usr/bin/env bun

// Script to fix all hardcoded pool IDs in trading scripts
import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const WRONG_POOL_ID = '0xdb86d006b7f5ba7afb160f08da976bf53d7254e25da80f1dda0a5d36d26d656d';

// Files that need to be fixed
const FILES_TO_FIX = [
  'testPercentageClosing.ts',
  'showPositions.ts', 
  'removeMargin.ts',
  'portfolioOverviewFixed.ts',
  'portfolioOverview.ts',
  'closePositionManaged.ts',
  'checkMarginRequirements.ts'
];

function addImports(content: string): string {
  // Check if imports already exist
  if (content.includes('calculateUsdcVethPoolId')) {
    return content;
  }

  // Find the import section and add our import
  const importMatch = content.match(/import.*from.*['"]\.\/contracts['"];/);
  if (importMatch) {
    return content.replace(
      importMatch[0],
      `${importMatch[0]}\nimport { calculateUsdcVethPoolId, getPoolInfo } from './poolUtils';`
    );
  }
  
  return content;
}

function replaceHardcodedPoolId(content: string): string {
  // Replace hardcoded pool ID with dynamic calculation
  const patterns = [
    // Pattern 1: Direct usage in function calls
    {
      search: new RegExp(`args: \\['${WRONG_POOL_ID}'\\]`, 'g'),
      replace: 'args: [poolId]'
    },
    // Pattern 2: With comments
    {
      search: new RegExp(`args: \\['${WRONG_POOL_ID}'\\] // Our pool ID`, 'g'), 
      replace: 'args: [poolId]'
    },
    // Pattern 3: Multi-line with other parameters
    {
      search: new RegExp(`args: \\['${WRONG_POOL_ID}',`, 'g'),
      replace: 'args: [poolId,'
    }
  ];

  let updatedContent = content;
  patterns.forEach(pattern => {
    updatedContent = updatedContent.replace(pattern.search, pattern.replace);
  });

  return updatedContent;
}

function addPoolIdCalculation(content: string): string {
  // Check if pool ID calculation already exists
  if (content.includes('calculateUsdcVethPoolId')) {
    return content;
  }

  // Find where to insert pool ID calculation
  // Look for the first usage of getMarkPrice or similar function
  const insertPoint = content.search(/const \w+ = await publicClient\.readContract\(/);
  
  if (insertPoint !== -1) {
    const beforeInsert = content.substring(0, insertPoint);
    const afterInsert = content.substring(insertPoint);
    
    const poolIdCode = `  // Calculate pool ID dynamically
  const poolId = calculateUsdcVethPoolId(c.mockUSDC.address, c.mockVETH.address, c.perpsHook.address);
  console.log('🆔 Using Pool ID:', poolId);

  `;
    
    return beforeInsert + poolIdCode + afterInsert;
  }
  
  return content;
}

function fixFile(filename: string): void {
  const filepath = join(__dirname, filename);
  
  try {
    console.log(`🔧 Fixing ${filename}...`);
    
    let content = readFileSync(filepath, 'utf8');
    
    // Step 1: Add imports
    content = addImports(content);
    
    // Step 2: Add pool ID calculation
    content = addPoolIdCalculation(content);
    
    // Step 3: Replace hardcoded pool IDs
    content = replaceHardcodedPoolId(content);
    
    // Write back the file
    writeFileSync(filepath, content, 'utf8');
    console.log(`✅ Fixed ${filename}`);
    
  } catch (error) {
    console.error(`❌ Error fixing ${filename}:`, error);
  }
}

function main() {
  console.log('🚀 Fixing all hardcoded pool IDs...');
  console.log(`❌ Wrong Pool ID: ${WRONG_POOL_ID}`);
  console.log('✅ Will replace with dynamic calculation\n');
  
  FILES_TO_FIX.forEach(fixFile);
  
  console.log('\n🎉 All files processed!');
  console.log('\n📋 Manual verification needed:');
  console.log('  1. Check that imports are correct');
  console.log('  2. Verify pool ID calculation placement');
  console.log('  3. Test each script to ensure it works');
}

main();
