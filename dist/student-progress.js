export const normalizeSearch=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR').trim();
export function searchMaterials(items,query){const terms=normalizeSearch(query).split(/\s+/).filter(Boolean);return items.filter(i=>i.kind==='material'&&terms.every(term=>normalizeSearch(i.title+' '+(i.body||'')).includes(term)))}
export function studentProgress(school,id,attempts=[]){
 const grades=school.grades.filter(g=>g.studentId===id).map(g=>({...g,assessment:school.assessments.find(a=>a.id===g.assessmentId)})).sort((a,b)=>(a.assessment?.date||'').localeCompare(b.assessment?.date||'')||a.assessmentId.localeCompare(b.assessmentId));
 const attendance=school.attendance.filter(a=>a.studentId===id).sort((a,b)=>b.date.localeCompare(a.date));const present=attendance.filter(a=>a.status==='present').length,absent=attendance.filter(a=>a.status==='absent').length,excused=attendance.filter(a=>a.status==='excused').length;
 const quizzes=[...attempts].sort((a,b)=>a.submitted_at.localeCompare(b.submitted_at));const correct=quizzes.reduce((n,q)=>n+q.correct_count,0),questions=quizzes.reduce((n,q)=>n+q.question_count,0);
 return {grades,average:grades.length?grades.reduce((n,g)=>n+Number(g.value),0)/grades.length:null,change:grades.length>1?Number(grades.at(-1).value)-Number(grades[0].value):null,attendance,present,absent,excused,frequency:present+absent?present/(present+absent)*100:null,quizzes,correct,questions,accuracy:questions?correct/questions*100:null};
}
