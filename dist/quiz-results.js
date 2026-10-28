// Attempts come only from the coordinator-only, RLS-protected table.
export function quizQuestionResults(questions,attempts){
 const total=attempts.length;
 const results=questions.map((q,index)=>{const alternatives=q.options.map(o=>({id:o.id,text:o.text,correct:o.id===q.correct_option_id,count:attempts.filter(a=>a.answers?.[q.id]===o.id).length}));const correct=alternatives.find(o=>o.correct)?.count||0;return {id:q.id,index:index+1,prompt:q.prompt,explanation:q.explanation||'',alternatives,correct,incorrect:total-correct,total,rate:total?Math.round(correct/total*100):null}});
 const correct=results.reduce((sum,q)=>sum+q.correct,0),possible=total*questions.length;
 return {total,questionCount:questions.length,rate:possible?Math.round(correct/possible*100):null,questions:results.sort((a,b)=>b.incorrect-a.incorrect||a.index-b.index)};
}
