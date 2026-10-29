export function practiceQuizResult(detail,answers){
 if(!detail.result||!Array.isArray(detail.questions)||!detail.questions.length)throw Error('Conclua a tentativa oficial antes de treinar.');
 let correct=0;for(const q of detail.questions){if(!q.options.some(o=>o.id===q.correct_option_id))throw Error('O gabarito deste quiz não está disponível.');if(!q.options.some(o=>o.id===answers[q.id]))throw Error('Responda todas as questões.');if(answers[q.id]===q.correct_option_id)correct++}
 return {...detail,can_submit:false,result:{correct_count:correct,question_count:detail.questions.length,answers:{...answers}}};
}
